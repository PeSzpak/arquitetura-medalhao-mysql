-- =====================================================================
-- CAMADA BRONZE - dados brutos, exatamente como chegam dos sistemas
-- AgroTech Digital
--
-- Tudo é texto: a Bronze não converte nem corrige nada. Os tratamentos
-- acontecem só na carga da Silver, e estes registros nunca são alterados.
-- =====================================================================
SET NAMES utf8mb4;

DROP DATABASE IF EXISTS db_bronze;
CREATE DATABASE db_bronze CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE db_bronze;

CREATE TABLE tb_clientes (
    id_cliente   INT PRIMARY KEY,
    nome         VARCHAR(150),
    email        VARCHAR(150),
    origem       VARCHAR(30)
);

CREATE TABLE tb_vendas (
    id_venda     INT PRIMARY KEY,
    id_cliente   INT,
    data_venda   VARCHAR(30),
    valor        VARCHAR(30),
    origem       VARCHAR(30)
);

INSERT INTO tb_clientes (id_cliente, nome, email, origem) VALUES
(1,  '  Ana Souza ',      'ana.souza@gmail.com',          'CRM'),
(2,  'Bruno Lima',        'bruno.lima@gmail',             'APP'),       -- @gmail sem .com
(3,  'Carla Mendes',      'carla@empresa.com.br',         'CRM'),
(4,  'Diego Rocha',       'diego.rocha@',                 'APP'),       -- incompleto
(5,  'Elisa Ferraz',      ' ELISA.FERRAZ@HOTMAIL.COM ',   'PLANILHA'),  -- maiúsculas e espaços
(6,  'Fábio Nunes',       'fabio.nunes',                  'PLANILHA'),  -- sem @
(7,  'Gabriela Tavares',  'gabi@gmail',                   'APP'),       -- @gmail sem .com
(8,  'Henrique Prado',    'henrique@agrotech',            'CRM'),       -- sem domínio, não é gmail
(9,  'Isabela Martins',   'isabela.martins@outlook.com',  'CRM'),
(10, 'João Pedro Alves',  NULL,                           'PLANILHA');  -- sem e-mail

INSERT INTO tb_vendas (id_venda, id_cliente, data_venda, valor, origem) VALUES
(101, 1,  '2024-01-15', '1.200,00',  'LOJA'),
(102, 1,  '2024/02/10', '399,90',    'SITE'),
(103, 2,  '15-03-2024', '150.5',     'APP'),
(104, 2,  '2024.04.05', '75.50',     'LOJA'),
(105, 3,  '2024-05-20', '2.350,75',  'SITE'),
(106, 3,  '2024/05/21', 'NaN',       'SITE'),   -- valor não numérico
(107, 4,  '2024-06-01', '0',         'APP'),    -- valor zero
(108, 5,  '01-07-2024', '-50,00',    'LOJA'),   -- valor negativo
(109, 5,  '2024.07.12', '980',       'LOJA'),
(110, 99, '2024-07-15', '500,00',    'SITE'),   -- cliente não existe
(111, 6,  '2024-02-30', '300,00',    'APP'),    -- 30 de fevereiro
(112, 6,  '20/08/2024', '120,00',    'APP'),    -- formato não reconhecido
(113, 7,  '2024-09-03', '89,90',     'APP'),
(114, 7,  '03-09-2024', 'abc',       'APP'),    -- valor não numérico
(115, 8,  '2024-10-10', '1.050,00',  'LOJA'),
(116, 98, 'data errada','NaN',       'SITE'),   -- três problemas: vale o primeiro (cliente)
(117, 4,  '31-12-2024', '45,00',     'LOJA'),
(118, 6,  '2024/11/31', '10,00',     'SITE'),   -- 31 de novembro
(119, 9,  '2024-11-05', '',          'SITE'),   -- valor vazio
(120, 8,  '2024.12.24', ' 250,00 ',  'LOJA'),   -- espaços em volta
(121, 3,  '2024-13-01', '80,00',     'SITE'),   -- mês 13
(122, 5,  NULL,         '60,00',     'APP');    -- sem data
