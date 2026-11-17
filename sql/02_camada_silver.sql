-- =====================================================================
-- CAMADA SILVER - dados tratados, padronizados e validados
-- =====================================================================
SET NAMES utf8mb4;

DROP DATABASE IF EXISTS db_silver;
CREATE DATABASE db_silver CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE db_silver;

CREATE TABLE tb_clientes (
    id_cliente      INT PRIMARY KEY,
    nome            VARCHAR(150) NOT NULL,
    email           VARCHAR(150) NULL,             -- NULL quando o e-mail é INVALIDO
    email_original  VARCHAR(150) NULL,             -- rastreabilidade com a Bronze
    status_email    ENUM('VALIDO', 'CORRIGIDO', 'INVALIDO') NOT NULL
);

CREATE TABLE tb_vendas (
    id_venda    INT PRIMARY KEY,                   -- identificador original da Bronze
    id_cliente  INT NOT NULL,
    data_venda  DATE NOT NULL,
    valor       DECIMAL(12,2) NOT NULL CHECK (valor > 0),
    CONSTRAINT fk_vendas_cliente FOREIGN KEY (id_cliente) REFERENCES tb_clientes (id_cliente)
);

CREATE TABLE tb_vendas_rejeitadas (
    id_venda        INT PRIMARY KEY,
    id_cliente      INT NULL,
    data_original   VARCHAR(30) NULL,
    valor_original  VARCHAR(30) NULL,
    motivo          ENUM('CLIENTE_INEXISTENTE', 'VALOR_INVALIDO', 'VALOR_NAO_POSITIVO', 'DATA_INVALIDA') NOT NULL
);
