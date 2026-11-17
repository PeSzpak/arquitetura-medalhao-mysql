-- =====================================================================
-- CAMADA GOLD - tabela analítica, uma linha por cliente
-- =====================================================================
SET NAMES utf8mb4;

DROP DATABASE IF EXISTS db_gold;
CREATE DATABASE db_gold CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE db_gold;

CREATE TABLE tb_relatorio_vendas (
    id_cliente     INT PRIMARY KEY,
    nome_cliente   VARCHAR(150) NOT NULL,
    total_vendas   DECIMAL(12,2) NOT NULL,
    qtd_vendas     INT NOT NULL,
    ticket_medio   DECIMAL(12,2) NOT NULL,
    atualizado_em  DATETIME NOT NULL
);

-- Schema que guarda as Stored Procedures do pipeline
DROP DATABASE IF EXISTS db_sp;
CREATE DATABASE db_sp CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
