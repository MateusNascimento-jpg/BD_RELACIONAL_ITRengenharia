DROP DATABASE IF EXISTS ITRengenhariaLOGIN; 
CREATE DATABASE ITRengenhariaLOGIN;
USE ITRengenhariaLOGIN;


-- <<<<<<<<<<<<<<<<<<< PARTE 1: TABELA PRINCIPAL DE USUÁRIOS >>>>>>>>>>>>>>>>>>

CREATE TABLE usuarios_cnpj (
    id                 INT AUTO_INCREMENT PRIMARY KEY,
    cnpj               VARCHAR(18)  NOT NULL UNIQUE, -- O UNIQUE garante que o CNPJ nunca se repita
    email              VARCHAR(150) NULL UNIQUE,     -- O UNIQUE garante que o E-mail nunca se repita
    senha_hash         VARCHAR(255) NOT NULL,
    status_conta       ENUM('Ativo', 'Inativo', 'Bloqueado') DEFAULT 'Ativo',
    data_cadastro      TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    ultima_atualizacao TIMESTAMP    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    -- Restrições de Validação (Robustez de Dados)
    CONSTRAINT chk_cnpj_formato   CHECK (LENGTH(cnpj) >= 11),
    CONSTRAINT chk_email_formato  CHECK (email LIKE '%@%.%' OR email IS NULL),
    -- O hash do Bcrypt tem sempre 60 caracteres. Limitado para evitar estouro de memória/ataques
    CONSTRAINT chk_senha_segura   CHECK (LENGTH(senha_hash) = 60)
);

-- PERFORMANCE: Índices para acelerar as buscas de Login e Autenticação
CREATE INDEX idx_usuarios_cnpj  ON usuarios_cnpj(cnpj);
CREATE INDEX idx_usuarios_email ON usuarios_cnpj(email);


-- <<<<<<<<<<<<<<<<<<<<<< PARTE 2: TABELA DE AUDITORIA (LOG PADRONIZADO) >>>>>>>>>>>>>>>>>>>>

CREATE TABLE auditoria_usuarios (
    `ID da Auditoria`     INT AUTO_INCREMENT PRIMARY KEY,
    `ID do Usuário`       INT,
    `CNPJ Afetado`        VARCHAR(18),
    `Ação Realizada`      VARCHAR(100),            
    `Operador do Sistema` VARCHAR(100), -- Guardará o e-mail do usuário real capturado pelo Node.js
    `Data e Hora da Ação` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


-- <<<<<<<<<<<<<<<<<<<<<<<< PARTE 3: A PROCEDURE (COM TRATAMENTO DE ERROS E TRANSAÇÕES) >>>>>>>>>>>>>>>>>>>>>>>>> 

DELIMITER $$

CREATE PROCEDURE procedure_cadastrar_usuario_cnpj(
    IN p_cnpj VARCHAR(18),
    IN p_email VARCHAR(150), 
    IN p_senha_hash VARCHAR(255),
    IN p_operador VARCHAR(100) -- ROBUSTEZ: O Node.js passa quem está logado fazendo a ação
)
BEGIN
    -- Garantia que o CPF, Senha ou Email não será cadastrado mais de uma vez dentro do sistema 
    DECLARE EXIT HANDLER FOR 1062
    BEGIN
        ROLLBACK; -- Desfaz qualquer operação em caso de erro duplicado
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERRO: Este CNPJ ou E-mail já encontra-se cadastrado no sistema.';
    END;

    -- Captura qualquer outro erro inesperado do banco
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERRO: Ocorreu uma falha interna ao tentar processar o cadastro.';
    END;

    -- ROBUSTEZ: Define uma variável de sessão temporária que os Triggers conseguem ler
    SET @usuario_sessao = p_operador;

    START TRANSACTION;
        INSERT INTO usuarios_cnpj (cnpj, email, senha_hash) 
        VALUES (p_cnpj, p_email, p_senha_hash);
    COMMIT;
END $$

DELIMITER ;


-- <<<<<<<<<<<<<<<<<<<<<<<<<< PARTE 4: TRIGGERS AUTOMÁTICOS >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 

-- Trigger A: Monitora novos cadastros

DELIMITER $$
CREATE TRIGGER tg_auditoria_inserir
AFTER INSERT ON usuarios_cnpj
FOR EACH ROW
BEGIN
    INSERT INTO auditoria_usuarios (`ID do Usuário`, `CNPJ Afetado`, `Ação Realizada`, `Operador do Sistema`)
    VALUES (NEW.id, NEW.cnpj, 'CADASTRO DE USUÁRIO', COALESCE(@usuario_sessao, USER()));
END$$
DELIMITER ;


-- Trigger B: Monitora atualizações e trocas de status
 
DELIMITER $$
CREATE TRIGGER tg_auditoria_atualizar
AFTER UPDATE ON usuarios_cnpj
FOR EACH ROW
BEGIN
    INSERT INTO auditoria_usuarios (`ID do Usuário`, `CNPJ Afetado`, `Ação Realizada`, `Operador do Sistema`)
    VALUES (NEW.id, NEW.cnpj, CONCAT('ALTERAÇÃO DE DADOS (Status anterior: ', OLD.status_conta, ' -> Novo: ', NEW.status_conta, ')'), COALESCE(@usuario_sessao, USER()));
END$$
DELIMITER ;


-- Trigger C: Monitora se alguém deletar uma conta do sistema

DELIMITER $$
CREATE TRIGGER tg_auditoria_excluir
AFTER DELETE ON usuarios_cnpj
FOR EACH ROW
BEGIN
    INSERT INTO auditoria_usuarios (`ID do Usuário`, `CNPJ Afetado`, `Ação Realizada`, `Operador do Sistema`)
    VALUES (OLD.id, OLD.cnpj, 'EXCLUSÃO DEFINITIVA DA CONTA', COALESCE(@usuario_sessao, USER()));
END$$
DELIMITER ;



-- <<<<<<<<<<<<<<<<<<<<< PARTE 5: TESTE PRÁTICO DO COFRE >>>>>>>>>>>>>>>>>>>>>>>>> 

-- 1. Primeiro cadastro (String simulada de hash com exatamente 60 caracteres)
CALL procedure_cadastrar_usuario_cnpj(
    '99.888.777/0001-11', 
    'contato@itr.com', 
    '$11111111111111111111111111111111111111111111111111111111111', 
    'admin_ti@itr.com'
);

SELECT * FROM usuarios_cnpj; 

-- 2. Teste de Duplicidade (Bloqueio) 
 -- CALL procedure_cadastrar_usuario_cnpj('99.888.777/0001-11', 'outro_email@itr.com', '$111111111111111111111111111111111111111111111111111111111111', 'admin_ti@itr.com');


-- 3. Mudando o status para ver a mensagem dinâmica do Trigger B
SET @usuario_sessao = 'sistema_automatico@itr.com'; -- Simulando o operador alterando o status
UPDATE usuarios_cnpj SET status_conta = 'bloqueado' WHERE cnpj = '99.888.777/0001-11';

-- 4. Deletando o usuário para ativar o Trigger C
SET @usuario_sessao = 'diretor_seguranca@itr.com'; -- Simulando quem mandou deletar
DELETE FROM usuarios_cnpj WHERE cnpj = '99.888.777/0001-11';


-- <<<<<<<<<<<<<<<<<<<<< VISUALIZAÇÃO DOS RESULTADOS >>>>>>>>>>>>>>>>>>>>>>>>> 

-- CONSULTA 1: A tabela principal estará vazia porque o usuário do teste foi deletado no fim
SELECT * FROM usuarios_cnpj;

-- CONSULTA 2: A tabela de auditoria mostrará todo o histórico padronizado com os operadores REAIS do sistema!
SELECT * FROM auditoria_usuarios;

