-- =====================================================================
-- HANDS-ON - Engenharia de Dados: Stored Procedures e Arquitetura Medalhão
-- Banco de Dados II - Pedro Szpak
-- Empresa fictícia: AgroTech Digital
--
-- Pré-requisito: rodar antes sql/01_camada_bronze.sql, sql/02_camada_silver.sql
-- e sql/03_camada_gold.sql (ou os scripts equivalentes do professor).
--
-- Fluxo:  Bronze (bruto)  ->  sp_carregar_silver  ->  Silver (tratado)
--                         ->  sp_carregar_gold    ->  Gold (analítico)
-- =====================================================================
SET NAMES utf8mb4;
USE db_sp;


-- =====================================================================
-- PARTE 1 - PROCEDURE SILVER (Bronze -> Silver)
-- =====================================================================

-- ---------------------------------------------------------------------
-- Função auxiliar: texto -> DATE (Requisito 1)
-- Reconhece YYYY-MM-DD, YYYY/MM/DD, YYYY.MM.DD e DD-MM-YYYY.
-- Devolve NULL para formatos desconhecidos e datas impossíveis
-- (30/02, 31/11, mês 13). A data é montada só depois de validada:
-- assim o modo estrito do MySQL não transforma a data ruim em erro
-- que derrubaria a carga inteira.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_converter_data;
DELIMITER $$
CREATE FUNCTION fn_converter_data(p_texto VARCHAR(30))
RETURNS DATE
DETERMINISTIC NO SQL
BEGIN
    DECLARE v_texto VARCHAR(30) DEFAULT TRIM(p_texto);
    DECLARE v_ano INT;
    DECLARE v_mes INT;
    DECLARE v_dia INT;
    DECLARE v_primeiro_dia DATE;

    IF v_texto IS NULL THEN
        RETURN NULL;
    ELSEIF v_texto REGEXP '^[0-9]{4}[-/.][0-9]{2}[-/.][0-9]{2}$'
           AND SUBSTRING(v_texto, 5, 1) = SUBSTRING(v_texto, 8, 1) THEN
        -- YYYY-MM-DD, YYYY/MM/DD ou YYYY.MM.DD (mesmo separador nas duas posições)
        SET v_ano = SUBSTRING(v_texto, 1, 4);
        SET v_mes = SUBSTRING(v_texto, 6, 2);
        SET v_dia = SUBSTRING(v_texto, 9, 2);
    ELSEIF v_texto REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$' THEN
        -- DD-MM-YYYY
        SET v_dia = SUBSTRING(v_texto, 1, 2);
        SET v_mes = SUBSTRING(v_texto, 4, 2);
        SET v_ano = SUBSTRING(v_texto, 7, 4);
    ELSE
        RETURN NULL;
    END IF;

    IF v_ano < 1900 OR v_mes NOT BETWEEN 1 AND 12 OR v_dia < 1 THEN
        RETURN NULL;
    END IF;

    SET v_primeiro_dia = MAKEDATE(v_ano, 1) + INTERVAL (v_mes - 1) MONTH;
    IF v_dia > DAY(LAST_DAY(v_primeiro_dia)) THEN
        RETURN NULL;
    END IF;

    RETURN v_primeiro_dia + INTERVAL (v_dia - 1) DAY;
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- Função auxiliar: texto -> DECIMAL(12,2) (Requisito 2)
--   '1.200,00' -> 1200.00   (padrão brasileiro com milhar)
--   '399,90'   -> 399.90    (vírgula decimal)
--   '150.5'    -> 150.50    (ponto decimal)
--   'NaN', 'abc', ''  -> NULL (não numérico)
-- Zero e negativos são números válidos aqui; a procedure é que os rejeita
-- com o motivo VALOR_NAO_POSITIVO.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_converter_valor;
DELIMITER $$
CREATE FUNCTION fn_converter_valor(p_texto VARCHAR(30))
RETURNS DECIMAL(12,2)
DETERMINISTIC NO SQL
BEGIN
    DECLARE v_texto VARCHAR(30) DEFAULT TRIM(p_texto);

    IF v_texto IS NULL OR v_texto = '' THEN
        RETURN NULL;
    ELSEIF v_texto REGEXP '^-?[0-9]{1,3}([.][0-9]{3})+,[0-9]{1,2}$' THEN
        SET v_texto = REPLACE(REPLACE(v_texto, '.', ''), ',', '.');
    ELSEIF v_texto REGEXP '^-?[0-9]+,[0-9]{1,2}$' THEN
        SET v_texto = REPLACE(v_texto, ',', '.');
    ELSEIF NOT v_texto REGEXP '^-?[0-9]+([.][0-9]{1,2})?$' THEN
        RETURN NULL;
    END IF;

    RETURN CAST(v_texto AS DECIMAL(12,2));
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- Procedure: db_sp.sp_carregar_silver()
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_carregar_silver;
DELIMITER $$
CREATE PROCEDURE sp_carregar_silver()
BEGIN
    -- Requisito 5: qualquer erro desfaz tudo e devolve o erro original
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Limpeza controlada: DELETE (e não TRUNCATE, que faria COMMIT implícito),
    -- das tabelas filhas para a tabela pai por causa da chave estrangeira.
    DELETE FROM db_silver.tb_vendas_rejeitadas;
    DELETE FROM db_silver.tb_vendas;
    DELETE FROM db_silver.tb_clientes;

    -- Requisito 3: todos os clientes entram, com o e-mail classificado
    INSERT INTO db_silver.tb_clientes (id_cliente, nome, email, email_original, status_email)
    SELECT
        b.id_cliente,
        TRIM(b.nome),
        CASE
            WHEN e.email_limpo REGEXP '^[a-z0-9._%+-]+@[a-z0-9-]+([.][a-z0-9-]+)*[.][a-z]{2,}$' THEN e.email_limpo
            WHEN e.email_limpo REGEXP '^[a-z0-9._%+-]+@gmail$' THEN CONCAT(e.email_limpo, '.com')
            ELSE NULL
        END,
        b.email,
        CASE
            WHEN e.email_limpo REGEXP '^[a-z0-9._%+-]+@[a-z0-9-]+([.][a-z0-9-]+)*[.][a-z]{2,}$' THEN 'VALIDO'
            WHEN e.email_limpo REGEXP '^[a-z0-9._%+-]+@gmail$' THEN 'CORRIGIDO'
            ELSE 'INVALIDO'
        END
    FROM db_bronze.tb_clientes b
    CROSS JOIN LATERAL (SELECT LOWER(TRIM(b.email)) AS email_limpo) e;

    -- Requisito 4: classifica cada venda uma única vez, já com o motivo
    -- principal na ordem pedida (cliente, valor inválido, valor não positivo, data)
    DROP TEMPORARY TABLE IF EXISTS tmp_vendas_classificadas;
    CREATE TEMPORARY TABLE tmp_vendas_classificadas AS
    SELECT
        t.*,
        CASE
            WHEN t.cliente_existe = 0 THEN 'CLIENTE_INEXISTENTE'
            WHEN t.valor_convertido IS NULL THEN 'VALOR_INVALIDO'
            WHEN t.valor_convertido <= 0 THEN 'VALOR_NAO_POSITIVO'
            WHEN t.data_convertida IS NULL THEN 'DATA_INVALIDA'
        END AS motivo
    FROM (
        SELECT
            b.id_venda,
            b.id_cliente,
            b.data_venda,
            b.valor,
            EXISTS (SELECT 1 FROM db_silver.tb_clientes c WHERE c.id_cliente = b.id_cliente) AS cliente_existe,
            db_sp.fn_converter_valor(b.valor) AS valor_convertido,
            db_sp.fn_converter_data(b.data_venda) AS data_convertida
        FROM db_bronze.tb_vendas b
    ) t;

    -- Vendas válidas, preservando o id original
    INSERT INTO db_silver.tb_vendas (id_venda, id_cliente, data_venda, valor)
    SELECT id_venda, id_cliente, data_convertida, valor_convertido
    FROM tmp_vendas_classificadas
    WHERE motivo IS NULL;

    -- Vendas rejeitadas, com os valores originais para auditoria
    INSERT INTO db_silver.tb_vendas_rejeitadas (id_venda, id_cliente, data_original, valor_original, motivo)
    SELECT id_venda, id_cliente, data_venda, valor, motivo
    FROM tmp_vendas_classificadas
    WHERE motivo IS NOT NULL;

    COMMIT;

    DROP TEMPORARY TABLE IF EXISTS tmp_vendas_classificadas;
END$$
DELIMITER ;


-- =====================================================================
-- PARTE 2 - PROCEDURE GOLD (Silver -> Gold)
-- =====================================================================

DROP PROCEDURE IF EXISTS sp_carregar_gold;
DELIMITER $$
CREATE PROCEDURE sp_carregar_gold()
BEGIN
    -- Requisito 4: falha no meio não deixa a Gold pela metade
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_resumo_vendas;
        RESIGNAL;
    END;

    -- Requisito 3: resultado intermediário em tabela temporária
    DROP TEMPORARY TABLE IF EXISTS tmp_resumo_vendas;
    CREATE TEMPORARY TABLE tmp_resumo_vendas (
        id_cliente    INT PRIMARY KEY,
        nome_cliente  VARCHAR(150) NOT NULL,
        total_vendas  DECIMAL(12,2) NOT NULL,
        qtd_vendas    INT NOT NULL,
        ticket_medio  DECIMAL(12,2) NOT NULL
    );

    -- Requisitos 1 e 2: uma linha por cliente; LEFT JOIN mantém quem não
    -- tem venda válida, e COALESCE transforma o NULL das agregações em zero
    INSERT INTO tmp_resumo_vendas (id_cliente, nome_cliente, total_vendas, qtd_vendas, ticket_medio)
    SELECT
        c.id_cliente,
        c.nome,
        COALESCE(SUM(v.valor), 0),
        COUNT(v.id_venda),
        COALESCE(ROUND(AVG(v.valor), 2), 0)
    FROM db_silver.tb_clientes c
    LEFT JOIN db_silver.tb_vendas v ON v.id_cliente = c.id_cliente
    GROUP BY c.id_cliente, c.nome;

    -- Troca o conteúdo da Gold numa única transação: quem consulta vê a
    -- versão antiga ou a nova, nunca uma tabela vazia ou incompleta
    START TRANSACTION;
    DELETE FROM db_gold.tb_relatorio_vendas;
    INSERT INTO db_gold.tb_relatorio_vendas
        (id_cliente, nome_cliente, total_vendas, qtd_vendas, ticket_medio, atualizado_em)
    SELECT id_cliente, nome_cliente, total_vendas, qtd_vendas, ticket_medio, NOW()
    FROM tmp_resumo_vendas;
    COMMIT;

    DROP TEMPORARY TABLE IF EXISTS tmp_resumo_vendas;
END$$
DELIMITER ;


-- =====================================================================
-- PARTE 3 - EXECUÇÃO E CONSULTAS DE VALIDAÇÃO
-- =====================================================================

-- ---------------------------------------------------------------------
-- Teste 1 - Processamento da Silver
-- ---------------------------------------------------------------------
CALL db_sp.sp_carregar_silver();

SELECT id_cliente, nome, email, email_original, status_email
FROM db_silver.tb_clientes
ORDER BY id_cliente;

SELECT id_venda, id_cliente, data_venda, valor
FROM db_silver.tb_vendas
ORDER BY id_venda;

SELECT id_venda, id_cliente, data_original, valor_original, motivo
FROM db_silver.tb_vendas_rejeitadas
ORDER BY id_venda;

-- Toda venda da Bronze foi para exatamente um destino
SELECT
    (SELECT COUNT(*) FROM db_bronze.tb_vendas)            AS vendas_bronze,
    (SELECT COUNT(*) FROM db_silver.tb_vendas)            AS vendas_validas,
    (SELECT COUNT(*) FROM db_silver.tb_vendas_rejeitadas) AS vendas_rejeitadas;

-- ---------------------------------------------------------------------
-- Teste 2 - Processamento da Gold
-- ---------------------------------------------------------------------
CALL db_sp.sp_carregar_gold();

SELECT id_cliente, nome_cliente, total_vendas, qtd_vendas, ticket_medio
FROM db_gold.tb_relatorio_vendas
ORDER BY total_vendas DESC, id_cliente;

-- ---------------------------------------------------------------------
-- Teste 3 - Reexecução: as contagens devem ser as mesmas e não pode
-- haver id repetido em nenhuma tabela
-- ---------------------------------------------------------------------
CALL db_sp.sp_carregar_silver();
CALL db_sp.sp_carregar_gold();

SELECT 'silver.tb_clientes' AS tabela, COUNT(*) AS linhas, COUNT(DISTINCT id_cliente) AS ids_distintos FROM db_silver.tb_clientes
UNION ALL
SELECT 'silver.tb_vendas', COUNT(*), COUNT(DISTINCT id_venda) FROM db_silver.tb_vendas
UNION ALL
SELECT 'silver.tb_vendas_rejeitadas', COUNT(*), COUNT(DISTINCT id_venda) FROM db_silver.tb_vendas_rejeitadas
UNION ALL
SELECT 'gold.tb_relatorio_vendas', COUNT(*), COUNT(DISTINCT id_cliente) FROM db_gold.tb_relatorio_vendas;

-- A Bronze continua intacta depois das cargas
SELECT id_venda, data_venda, valor FROM db_bronze.tb_vendas WHERE id_venda IN (101, 103, 120);

-- ---------------------------------------------------------------------
-- Teste 4 - Conferência dos indicadores
-- ---------------------------------------------------------------------

-- Os três clientes com maior faturamento
SELECT nome_cliente, total_vendas
FROM db_gold.tb_relatorio_vendas
ORDER BY total_vendas DESC
LIMIT 3;

-- O cliente com maior ticket médio
SELECT nome_cliente, ticket_medio
FROM db_gold.tb_relatorio_vendas
ORDER BY ticket_medio DESC
LIMIT 1;

-- Clientes que não realizaram compras válidas
SELECT id_cliente, nome_cliente
FROM db_gold.tb_relatorio_vendas
WHERE qtd_vendas = 0
ORDER BY id_cliente;

-- Faturamento total na Silver
SELECT SUM(valor) AS faturamento_silver FROM db_silver.tb_vendas;

-- Faturamento total consolidado na Gold
SELECT SUM(total_vendas) AS faturamento_gold FROM db_gold.tb_relatorio_vendas;

-- As duas camadas precisam bater
SELECT
    (SELECT SUM(valor) FROM db_silver.tb_vendas)                AS silver,
    (SELECT SUM(total_vendas) FROM db_gold.tb_relatorio_vendas) AS gold,
    (SELECT SUM(valor) FROM db_silver.tb_vendas)
        = (SELECT SUM(total_vendas) FROM db_gold.tb_relatorio_vendas) AS confere;
