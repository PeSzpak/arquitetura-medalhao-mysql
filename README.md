# Arquitetura Medalhão com Stored Procedures (MySQL)

Hands-on de **Banco de Dados II** (ADS, Senac São José dos Pinhais). A empresa fictícia **AgroTech Digital** recebe dados de clientes e vendas de vários sistemas (CRM, app, site, planilhas), com datas em formatos diferentes, valores monetários fora de padrão, e-mails incompletos e vendas inválidas. Duas Stored Procedures levam esses dados da camada Bronze à Gold, prontos para relatório.

Os demais exercícios da disciplina estão em [SQL-Class](https://github.com/PeSzpak/SQL-Class).

## Onde a arquitetura medalhão se encaixa

Antes do pipeline, um resumo dos quatro jeitos mais comuns de guardar dados para análise.

### Data Warehouse

Banco analítico **estruturado**, com esquema definido antes da carga (*schema-on-write*). Os dados chegam por ETL já limpos, integrados e modelados, normalmente em fatos e dimensões (modelo estrela). É ótimo para relatórios e BI, com consultas rápidas e números confiáveis. Em troca, é rígido: guarda só dados estruturados, mudar o modelo custa caro e o armazenamento é mais caro.
*Exemplos:* Amazon Redshift, Google BigQuery, Snowflake, SQL Server.

### Data Lake

Repositório que guarda **qualquer dado no formato original**: tabelas, CSV, JSON, logs, imagens, áudio. O esquema só é aplicado na hora de ler (*schema-on-read*). Sai barato, escala muito e serve bem para ciência de dados e machine learning, porque nada é descartado. O risco é que, sem organização, ninguém sabe o que está lá dentro nem se dá para confiar.
*Exemplos:* Amazon S3, Azure Data Lake Storage, Google Cloud Storage.

### Data Swamp

É o **data lake que deu errado**: um "pântano" de dados. Arquivos entram sem catálogo, sem metadados, sem dono, sem controle de qualidade e sem regra de acesso. Aparecem cópias duplicadas, versões conflitantes e dados que ninguém sabe de onde vieram. O dado existe, mas não é encontrável nem confiável, e o lago vira custo sem valor. Não é uma arquitetura que alguém escolhe; é o resultado da falta de governança.

### Data Lakehouse

Junta as duas ideias: o **armazenamento barato e flexível do data lake** com os **recursos do data warehouse**, como transações ACID, esquema, versionamento, controle de acesso e consultas SQL rápidas. Isso acontece por meio de formatos de tabela abertos sobre os arquivos do lago, como Delta Lake, Apache Iceberg e Apache Hudi. A mesma base atende BI e machine learning sem copiar dados entre dois sistemas.
*Exemplos:* Databricks, Microsoft Fabric, Snowflake com Iceberg.

### Comparação rápida

| | Data Warehouse | Data Lake | Data Swamp | Data Lakehouse |
|---|---|---|---|---|
| Tipo de dado | Estruturado | Qualquer um | Qualquer um, sem controle | Qualquer um |
| Esquema | Na escrita | Na leitura | Inexistente na prática | Na escrita, com evolução |
| Qualidade | Alta | Varia | Baixa e desconhecida | Alta nas camadas tratadas |
| Custo de armazenamento | Alto | Baixo | Baixo, mas sem retorno | Baixo |
| Uso principal | BI e relatórios | Ciência de dados, ML, histórico bruto | Nenhum confiável | BI e ML na mesma base |

### E a arquitetura medalhão?

É a forma mais usada de **organizar um lakehouse** (ou um lake) para ele não virar pântano. Os dados passam por três camadas, e a qualidade sobe a cada uma:

| Camada | O que guarda | Neste projeto |
|---|---|---|
| **Bronze** | O dado bruto, como chegou. Nunca é alterado e serve de histórico e de fonte para reprocessar. | `db_bronze`: tudo em texto, com os erros originais |
| **Silver** | O dado limpo: tipos corretos, padronizado, validado, sem duplicidade. O que foi rejeitado fica registrado com o motivo. | `db_silver`: clientes com status do e-mail, vendas válidas e vendas rejeitadas |
| **Gold** | O dado pronto para o negócio: agregado, com indicadores, no formato que o relatório precisa. | `db_gold`: uma linha por cliente com total, quantidade e ticket médio |

Aqui as três camadas são schemas do MySQL e as transformações são Stored Procedures. Num lakehouse de verdade seriam tabelas Delta ou Iceberg processadas com Spark ou dbt, mas a lógica é a mesma.

## O pipeline

```text
db_bronze.tb_clientes ─┐                          ┌─► db_silver.tb_clientes ────────┐
                       ├─► sp_carregar_silver() ──┼─► db_silver.tb_vendas ──────────┼─► sp_carregar_gold() ─► db_gold.tb_relatorio_vendas
db_bronze.tb_vendas ───┘                          └─► db_silver.tb_vendas_rejeitadas│      (via tmp_resumo_vendas)
```

### `sp_carregar_silver()` (Bronze → Silver)

- **Datas:** reconhece `YYYY-MM-DD`, `YYYY/MM/DD`, `YYYY.MM.DD` e `DD-MM-YYYY`. Formatos desconhecidos (`20/08/2024`) e datas impossíveis (30/02, 31/11, mês 13) viram `DATA_INVALIDA`. A data só é montada depois de validada, para que o modo estrito do MySQL não derrube a carga.
- **Valores:** `1.200,00` → 1200.00, `399,90` → 399.90, `150.5` → 150.50. Texto como `NaN`, `abc` ou vazio vira `VALOR_INVALIDO`; zero e negativos viram `VALOR_NAO_POSITIVO`.
- **E-mails:** `VALIDO` (minúsculo e sem espaços), `CORRIGIDO` (terminava em `@gmail` e ganhou `.com`) ou `INVALIDO` (o campo fica `NULL`). Todos os clientes são mantidos, e o e-mail original fica guardado em `email_original`.
- **Vendas:** só entram as que têm cliente existente, valor positivo e data válida, preservando o `id_venda` original. As outras vão para `tb_vendas_rejeitadas`, com o primeiro motivo na ordem: cliente, valor inválido, valor não positivo, data.
- **Transação:** `START TRANSACTION`, limpeza com `DELETE` (o `TRUNCATE` faria commit implícito), cargas, `COMMIT`; qualquer erro dispara `ROLLBACK`.

### `sp_carregar_gold()` (Silver → Gold)

- Monta `tmp_resumo_vendas` com `SUM`, `COUNT` e `AVG` sobre `LEFT JOIN` de clientes com vendas, para que cliente sem venda apareça com zeros.
- Troca o conteúdo de `tb_relatorio_vendas` numa única transação e remove a tabela temporária ao final.

## Como rodar

```bash
mysql -u root -p < sql/01_camada_bronze.sql
mysql -u root -p < sql/02_camada_silver.sql
mysql -u root -p < sql/03_camada_gold.sql
mysql -u root -p < hands_on_medalhao.sql     # cria as procedures, executa e valida
```

`hands_on_medalhao.sql` é o arquivo de entrega: Parte 1 (procedure Silver), Parte 2 (procedure Gold) e Parte 3 (`CALL` e consultas de validação).

## Testes realizados (MySQL 8.4, 16/11/2026)

| Teste | Resultado |
|---|---|
| 1. Silver | 10 clientes (4 válidos, 2 corrigidos, 4 inválidos); 10 vendas válidas e 12 rejeitadas, somando as 22 da Bronze |
| 2. Gold | 10 linhas, uma por cliente; Fábio, Isabela e João com zero |
| 3. Reexecução | Mesmas contagens, nenhum id repetido, Bronze intacta |
| 4. Indicadores | Top 3: Carla (R$ 2.350,75), Ana (R$ 1.599,90), Henrique (R$ 1.300,00); maior ticket: Carla; faturamento Silver = Gold = **R$ 6.591,55** |
| Falha na Gold | Um gatilho derrubou a carga ao inserir o 6º cliente: a Gold manteve as 10 linhas da versão anterior, sem carga pela metade |
| Falha na Silver | Mesmo teste na venda 113: a Silver voltou inteira ao estado anterior (10 / 10 / 12) |

| Motivo de rejeição | Vendas |
|---|---|
| CLIENTE_INEXISTENTE | 110, 116 (a 116 tinha três problemas; vale o primeiro da ordem) |
| VALOR_INVALIDO | 106 (`NaN`), 114 (`abc`), 119 (vazio) |
| VALOR_NAO_POSITIVO | 107 (`0`), 108 (`-50,00`) |
| DATA_INVALIDA | 111 (30/02), 112 (`20/08/2024`), 118 (31/11), 121 (mês 13), 122 (sem data) |

## Sobre os scripts de preparação

O enunciado pede para rodar os scripts do professor (`01_camada_bronze.sql` a `05_checkpoints.sql`). Como eles não estavam disponíveis, os scripts da pasta `sql/` recriam o ambiente seguindo o enunciado, com dados que cobrem todos os casos pedidos. Com os scripts originais, as procedures valem igual; só os nomes das tabelas Bronze podem precisar de ajuste.
