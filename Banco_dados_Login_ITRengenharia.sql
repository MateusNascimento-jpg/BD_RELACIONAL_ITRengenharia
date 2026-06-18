DROP DATABASE IF EXISTS ITRengenhariaLOGIN; 
CREATE DATABASE ITRengenhariaLOGIN;
USE ITRengenhariaLOGIN;


-- <<<<<<<<<<<<<<<<<<< PARTE 1: TABELA PRINCIPAL DE USUÁRIOS >>>>>>>>>>>>>>>>>>

CREATE TABLE usuarios_cnpj (
    id                  INT AUTO_INCREMENT PRIMARY KEY,
    
    documento           VARCHAR(14)  NOT NULL UNIQUE,                                               -- ------> CPF ou CNPJ (apenas números, sem máscara)
    tipo_documento      ENUM('CPF', 'CNPJ') NOT NULL,                                               -- ------> Identifica se é CPF ou CNPJ
    email               VARCHAR(150) NULL UNIQUE,    -- O UNIQUE garante que o E-mail nunca se repita
    senha_hash          VARCHAR(255) NOT NULL,
    
    nome_empresa        VARCHAR(200) NULL,                                                          -- ------> Nome/razão social da empresa (ou nome do funcionário)
    perfil              ENUM('Cliente', 'Funcionario', 'Gerente_TI', 'Diretor') DEFAULT 'Cliente',  -- ------> Define o nível de acesso do usuário
    airtable_client_id  VARCHAR(50)  NULL,                                                          -- ------> Vincula o usuário ao cliente do Airtable
    reset_token         VARCHAR(255) NULL,                                                          -- ------> Token gerado quando o usuário esquece a senha
    reset_expires       TIMESTAMP    NULL,                                                          -- ------> Validade do token de recuperação (1 hora)
    ultimo_login        TIMESTAMP    NULL,                                                          -- ------> Marca a última vez que o usuário entrou no sistema
    
    tentativas_login    INT          DEFAULT 0,                                                     -- ------> Conta tentativas de login erradas seguidas
    bloqueado_ate       TIMESTAMP    NULL,                                                          -- ------> Data até a qual a conta está temporariamente bloqueada

    data_exclusao       TIMESTAMP    NULL,                                                          -- ------> [PROCEDURE SOFT DELETE] Em vez de deletar, marca a data para preservar histórico  na tabela de LOGS

    status_conta        ENUM('Ativo', 'Inativo', 'Bloqueado') DEFAULT 'Ativo',
    data_cadastro       TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    ultima_atualizacao  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    -- Restrições de Validação (Robustez de Dados)
    CONSTRAINT chk_documento_tamanho CHECK (LENGTH(documento) IN (11, 14)),                         -- ------> Garante 11 (CPF) ou 14 (CNPJ) dígitos
    CONSTRAINT chk_documento_numerico CHECK (documento REGEXP '^[0-9]+$'),                          -- ------> Garante que só tem números (sem máscara)
    CONSTRAINT chk_tipo_documento_coerente CHECK (                                                  -- ------> CPF deve ter 11 dígitos e CNPJ deve ter 14
        (tipo_documento = 'CPF'  AND LENGTH(documento) = 11) OR
        (tipo_documento = 'CNPJ' AND LENGTH(documento) = 14)
    ),
    CONSTRAINT chk_email_formato  CHECK (email LIKE '%@%.%' OR email IS NULL),
    CONSTRAINT chk_senha_segura   CHECK (LENGTH(senha_hash) = 60)
);

-- PERFORMANCE: Índices para acelerar as buscas
CREATE INDEX idx_usuarios_documento  ON usuarios_cnpj(documento);                                    -- ------> Acelera o login que busca por CPF/CNPJ
CREATE INDEX idx_usuarios_email      ON usuarios_cnpj(email);
CREATE INDEX idx_usuarios_perfil     ON usuarios_cnpj(perfil);                                       -- ------> Acelera consultas filtradas por perfil
CREATE INDEX idx_reset_token         ON usuarios_cnpj(reset_token);                                  -- ------> Acelera a validação do token de recuperação


-- <<<<<<<<<<<<<<<<<<< PARTE 2: TABELA DE PERMISSÕES POR PERFIL >>>>>>>>>>>>>>>>>>
-- ------> Tabela que define o que cada perfil pode fazer no sistema

CREATE TABLE permissoes_perfil (
    id           INT AUTO_INCREMENT PRIMARY KEY,
    perfil       ENUM('Cliente', 'Funcionario', 'Gerente_TI', 'Diretor') NOT NULL,    -- ------> Vincula a permissão ao perfil
    pode_ler     BOOLEAN DEFAULT FALSE,                                                -- ------> Permissão de leitura (SELECT)
    pode_criar   BOOLEAN DEFAULT FALSE,                                                -- ------> Permissão de criação (INSERT)
    pode_editar  BOOLEAN DEFAULT FALSE,                                                -- ------> Permissão de edição (UPDATE)
    pode_excluir BOOLEAN DEFAULT FALSE,                                                -- ------> Permissão de exclusão (DELETE)
    descricao    VARCHAR(255),                                                         -- ------> Descrição amigável das permissões
    UNIQUE KEY uk_perfil (perfil)                                                      -- ------> Garante uma única regra por perfil
);

-- ------> Inserção das permissões pré-definidas de cada perfil
INSERT INTO permissoes_perfil (perfil, pode_ler, pode_criar, pode_editar, pode_excluir, descricao) VALUES
('Cliente',     TRUE,  FALSE, FALSE, FALSE, 'Visualiza apenas seus próprios relatórios'),
('Funcionario', TRUE,  TRUE,  TRUE,  FALSE, 'Pode ler, criar e editar — não pode excluir'),
('Gerente_TI',  TRUE,  TRUE,  TRUE,  TRUE,  'Acesso total ao sistema'),
('Diretor',     TRUE,  TRUE,  TRUE,  TRUE,  'Acesso total ao sistema');


-- <<<<<<<<<<<<<<<<<<<<<< PARTE 3: TABELA DE AUDITORIA (LOG PADRONIZADO) >>>>>>>>>>>>>>>>>>>>

CREATE TABLE auditoria_usuarios (
    `ID da Auditoria`     INT AUTO_INCREMENT PRIMARY KEY,
    `ID do Usuário`       INT,
    `Documento Afetado`   VARCHAR(14),                            -- ------> Documento (CPF/CNPJ) do usuário afetado pela ação
    `Tipo Documento`      VARCHAR(10),                            -- ------> Indica se o documento é CPF ou CNPJ
    `Perfil do Usuário`   VARCHAR(50),                            -- ------> Registra qual perfil estava sendo afetado pela ação
    `Ação Realizada`      VARCHAR(100),            
    `Operador do Sistema` VARCHAR(100), -- Guardará o e-mail do usuário real capturado pelo Node.js
    `Data e Hora da Ação` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


-- <<<<<<<<<<<<<<<<<<< PARTE 4: TABELA DE SESSÕES ATIVAS >>>>>>>>>>>>>>>>>>
-- ------> [[[[[NOVA TABELA]]]] Guarda todas as sessões/tokens ativos para permitir logout forçado e revogar acessos comprometidos

CREATE TABLE sessoes_ativas (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    usuario_id      INT NOT NULL,                                                 
    token_sessao    VARCHAR(255) NOT NULL UNIQUE,                                  
    ip_origem       VARCHAR(45),                                                   
    navegador       VARCHAR(255),                                                  
    criada_em       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,                           
    expira_em       TIMESTAMP NOT NULL,                                         
    revogada        BOOLEAN DEFAULT FALSE,                                        
     
    FOREIGN KEY (usuario_id) REFERENCES usuarios_cnpj(id) ON DELETE CASCADE  
);  

CREATE INDEX idx_sessao_token   ON sessoes_ativas(token_sessao);                   
CREATE INDEX idx_sessao_usuario ON sessoes_ativas(usuario_id);     
                      


-- <<<<<<<<<<<<<<<<<<< PARTE 5: TABELA DE HISTÓRICO DE LOGINS >>>>>>>>>>>>>>>>>>
-- ------> [[[[NOVA TABELA]]]] Registra cada tentativa de login (sucesso ou falha) para auditoria de segurança e detecção de acessos suspeitos

CREATE TABLE historico_logins (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    usuario_id      INT NULL,                                                   
    sucesso         BOOLEAN NOT NULL,                                              
    ip_origem       VARCHAR(45),                                                   
    navegador       VARCHAR(255),                                                  
    motivo_falha    VARCHAR(100) NULL,                                             
    data_tentativa  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,                           
    
    FOREIGN KEY (usuario_id) REFERENCES usuarios_cnpj(id) ON DELETE SET NULL    
);

CREATE INDEX idx_historico_usuario   ON historico_logins(usuario_id);              -- ------> Acelera busca de histórico por usuário         
CREATE INDEX idx_historico_data      ON historico_logins(data_tentativa);          -- ------> Acelera filtros por período


-- <<<<<<<<<<<<<<<<<<<<<<<< PARTE 6: FUNÇÃO PARA VALIDAR CPF >>>>>>>>>>>>>>>>>>>>>>>>>
-- ------> Função que valida matematicamente os dígitos verificadores do CPF

DELIMITER $$

CREATE FUNCTION fn_validar_cpf(p_cpf VARCHAR(11)) 
RETURNS BOOLEAN
DETERMINISTIC
BEGIN
    DECLARE i INT DEFAULT 1;
    DECLARE soma INT DEFAULT 0;
    DECLARE digito1 INT DEFAULT 0;
    DECLARE digito2 INT DEFAULT 0;
    DECLARE resto INT DEFAULT 0;
    
    IF LENGTH(p_cpf) <> 11 THEN RETURN FALSE; END IF;
    IF p_cpf REGEXP '^([0-9])\\1{10}$' THEN RETURN FALSE; END IF;
    
    WHILE i <= 9 DO
        SET soma = soma + (CAST(SUBSTRING(p_cpf, i, 1) AS UNSIGNED) * (11 - i));
        SET i = i + 1;
    END WHILE;
    SET resto = soma % 11;
    SET digito1 = IF(resto < 2, 0, 11 - resto);
    
    IF digito1 <> CAST(SUBSTRING(p_cpf, 10, 1) AS UNSIGNED) THEN RETURN FALSE; END IF;
    
    SET soma = 0;
    SET i = 1;
    WHILE i <= 10 DO
        SET soma = soma + (CAST(SUBSTRING(p_cpf, i, 1) AS UNSIGNED) * (12 - i));
        SET i = i + 1;
    END WHILE;
    SET resto = soma % 11;
    SET digito2 = IF(resto < 2, 0, 11 - resto);
    
    IF digito2 <> CAST(SUBSTRING(p_cpf, 11, 1) AS UNSIGNED) THEN RETURN FALSE; END IF;
    
    RETURN TRUE;
END $$

DELIMITER ;


-- <<<<<<<<<<<<<<<<<<<<<<<< PARTE 7: FUNÇÃO PARA VALIDAR CNPJ >>>>>>>>>>>>>>>>>>>>>>>>>
-- ------> Função que valida matematicamente os dígitos verificadores do CNPJ

DELIMITER $$

CREATE FUNCTION fn_validar_cnpj(p_cnpj VARCHAR(14)) 
RETURNS BOOLEAN
DETERMINISTIC
BEGIN
    DECLARE i INT DEFAULT 1;
    DECLARE soma INT DEFAULT 0;
    DECLARE peso INT DEFAULT 5;
    DECLARE digito1 INT DEFAULT 0;
    DECLARE digito2 INT DEFAULT 0;
    DECLARE resto INT DEFAULT 0;
    
    IF LENGTH(p_cnpj) <> 14 THEN RETURN FALSE; END IF;
    IF p_cnpj REGEXP '^([0-9])\\1{13}$' THEN RETURN FALSE; END IF;
    
    WHILE i <= 12 DO
        SET soma = soma + (CAST(SUBSTRING(p_cnpj, i, 1) AS UNSIGNED) * peso);
        SET peso = IF(peso = 2, 9, peso - 1);
        SET i = i + 1;
    END WHILE;
    SET resto = soma % 11;
    SET digito1 = IF(resto < 2, 0, 11 - resto);
    
    IF digito1 <> CAST(SUBSTRING(p_cnpj, 13, 1) AS UNSIGNED) THEN RETURN FALSE; END IF;
    
    SET soma = 0;
    SET peso = 6;
    SET i = 1;
    WHILE i <= 13 DO
        SET soma = soma + (CAST(SUBSTRING(p_cnpj, i, 1) AS UNSIGNED) * peso);
        SET peso = IF(peso = 2, 9, peso - 1);
        SET i = i + 1;
    END WHILE;
    SET resto = soma % 11;
    SET digito2 = IF(resto < 2, 0, 11 - resto);
    
    IF digito2 <> CAST(SUBSTRING(p_cnpj, 14, 1) AS UNSIGNED) THEN RETURN FALSE; END IF;
    
    RETURN TRUE;
END $$

DELIMITER ;


-- <<<<<<<<<<<<<<<<<<<<<<<< PARTE 8: PROCEDURE DE CADASTRO >>>>>>>>>>>>>>>>>>>>>>>>> 

DELIMITER $$

CREATE PROCEDURE procedure_cadastrar_usuario_cnpj(
    IN p_documento VARCHAR(14),
    IN p_tipo_documento ENUM('CPF', 'CNPJ'),
    IN p_email VARCHAR(150), 
    IN p_senha_hash VARCHAR(255),
    IN p_nome_empresa VARCHAR(200),
    IN p_perfil ENUM('Cliente','Funcionario','Gerente_TI','Diretor'),
    IN p_airtable_client_id VARCHAR(50),
    IN p_operador VARCHAR(100)
)
BEGIN
    DECLARE EXIT HANDLER FOR 1062
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERRO: Este CPF/CNPJ ou E-mail já encontra-se cadastrado no sistema.';
    END;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERRO: Ocorreu uma falha interna ao tentar processar o cadastro.';
    END;

    IF p_tipo_documento = 'CPF' AND NOT fn_validar_cpf(p_documento) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERRO: CPF inválido. Verifique os dígitos.';
    END IF;
    
    IF p_tipo_documento = 'CNPJ' AND NOT fn_validar_cnpj(p_documento) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERRO: CNPJ inválido. Verifique os dígitos.';
    END IF;

    SET @usuario_sessao = p_operador;

    START TRANSACTION;
        INSERT INTO usuarios_cnpj (documento, tipo_documento, email, senha_hash, nome_empresa, perfil, airtable_client_id) 
        VALUES (p_documento, p_tipo_documento, p_email, p_senha_hash, p_nome_empresa, COALESCE(p_perfil, 'Cliente'), p_airtable_client_id);
    COMMIT;
END $$

DELIMITER ;


-- <<<<<<<<<<<<<<<<<<<<<<<< PARTE 9: PROCEDURE DE LOGIN >>>>>>>>>>>>>>>>>>>>>>>>> 

DELIMITER $$

CREATE PROCEDURE procedure_registrar_login(
    IN p_documento VARCHAR(14)
)
BEGIN
    UPDATE usuarios_cnpj 
    SET ultimo_login = CURRENT_TIMESTAMP,
        tentativas_login = 0,
        bloqueado_ate = NULL
    WHERE documento = p_documento AND status_conta = 'Ativo' AND data_exclusao IS NULL;     -- ------> Ignora usuários com soft delete
    
    SELECT id, documento, tipo_documento, email, nome_empresa, perfil, airtable_client_id, status_conta
    FROM usuarios_cnpj 
    WHERE documento = p_documento AND data_exclusao IS NULL;                                -- ------> Ignora usuários com soft delete
END $$

DELIMITER ;


-- <<<<<<<<<<<<<<<<<<<<<<<< PARTE 10: PROCEDURE DE TENTATIVA ERRADA >>>>>>>>>>>>>>>>>>>>>>>>> 

DELIMITER $$

CREATE PROCEDURE procedure_login_falhou(
    IN p_documento VARCHAR(14)
)
BEGIN
    DECLARE v_tentativas INT DEFAULT 0;
    
    SELECT tentativas_login INTO v_tentativas
    FROM usuarios_cnpj
    WHERE documento = p_documento;
    
    IF v_tentativas + 1 >= 5 THEN
        UPDATE usuarios_cnpj
        SET tentativas_login = v_tentativas + 1,
            bloqueado_ate = DATE_ADD(NOW(), INTERVAL 15 MINUTE)
        WHERE documento = p_documento;
    ELSE
        UPDATE usuarios_cnpj
        SET tentativas_login = v_tentativas + 1
        WHERE documento = p_documento;
    END IF;
    
    SELECT tentativas_login, bloqueado_ate
    FROM usuarios_cnpj 
    WHERE documento = p_documento;
END $$

DELIMITER ;


-- <<<<<<<<<<<<<<<<<<<<<<<< PARTE 11: PROCEDURE DE SOFT DELETE >>>>>>>>>>>>>>>>>>>>>>>>> 
-- ------> Procedure que marca o usuário como excluído sem apagar o registro (preserva auditoria e LGPD)

DELIMITER $$

CREATE PROCEDURE procedure_soft_delete_usuario(
    IN p_documento VARCHAR(14),                                                      -- ------> Documento do usuário a ser "excluído"
    IN p_operador VARCHAR(100)                                                        -- ------> Quem está executando a exclusão
)
BEGIN
    SET @usuario_sessao = p_operador;
    
    -- ------> Marca como inativo e registra a data, mas mantém todo o histórico no banco
    UPDATE usuarios_cnpj
    SET data_exclusao = CURRENT_TIMESTAMP,
        status_conta = 'Inativo'
    WHERE documento = p_documento AND data_exclusao IS NULL; 
    
    -- ------> Também revoga todas as sessões ativas do usuário
    UPDATE sessoes_ativas
    SET revogada = TRUE
    WHERE usuario_id = (SELECT id FROM usuarios_cnpj WHERE documento = p_documento); 
END $$ 

DELIMITER ;


-- <<<<<<<<<<<<<<<<<<<<<<<<<< PARTE 12: TRIGGERS AUTOMÁTICOS >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 

-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< Refazendo as triggers >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
DROP TRIGGER IF EXISTS tg_auditoria_inserir;
DROP TRIGGER IF EXISTS tg_auditoria_atualizar;
DROP TRIGGER IF EXISTS tg_auditoria_excluir;


-- Trigger A: Auditoria de cadastro (só para CNPJ)
DELIMITER $$
CREATE TRIGGER tg_auditoria_inserir
AFTER INSERT ON usuarios_cnpj
FOR EACH ROW
BEGIN
    IF NEW.tipo_documento = 'CNPJ' THEN                                          -- ------> Só registra logs de clientes (CNPJ)
        INSERT INTO auditoria_usuarios (`ID do Usuário`, `Documento Afetado`, `Tipo Documento`, `Perfil do Usuário`, `Ação Realizada`, `Operador do Sistema`)
        VALUES (NEW.id, NEW.documento, NEW.tipo_documento, NEW.perfil, 'CADASTRO DE USUÁRIO', COALESCE(@usuario_sessao, USER()));
    END IF;
END$$
DELIMITER ;



-- Trigger B: Auditoria de atualização (só para CNPJ)
DELIMITER $$
CREATE TRIGGER tg_auditoria_atualizar
AFTER UPDATE ON usuarios_cnpj
FOR EACH ROW
BEGIN
    IF NEW.tipo_documento = 'CNPJ' THEN                                          -- ------> Só registra logs de clientes (CNPJ)
        INSERT INTO auditoria_usuarios (`ID do Usuário`, `Documento Afetado`, `Tipo Documento`, `Perfil do Usuário`, `Ação Realizada`, `Operador do Sistema`)
        VALUES (
            NEW.id, NEW.documento, NEW.tipo_documento, NEW.perfil,
            CASE 
                WHEN OLD.data_exclusao IS NULL AND NEW.data_exclusao IS NOT NULL THEN 'SOFT DELETE - CONTA MARCADA COMO EXCLUÍDA'
                WHEN OLD.status_conta <> NEW.status_conta THEN CONCAT('STATUS: ', OLD.status_conta, ' -> ', NEW.status_conta)
                WHEN OLD.perfil <> NEW.perfil THEN CONCAT('PERFIL: ', OLD.perfil, ' -> ', NEW.perfil)
                WHEN COALESCE(OLD.airtable_client_id,'') <> COALESCE(NEW.airtable_client_id,'') THEN 'VÍNCULO AIRTABLE ATUALIZADO'
                WHEN NEW.bloqueado_ate IS NOT NULL AND OLD.bloqueado_ate IS NULL THEN 'CONTA BLOQUEADA POR EXCESSO DE TENTATIVAS'
                ELSE 'ATUALIZAÇÃO DE DADOS'
            END,
            COALESCE(@usuario_sessao, USER())
        );
    END IF;
END$$
DELIMITER ;


-- Trigger C: Auditoria de exclusão (só para CNPJ)
DELIMITER $$
CREATE TRIGGER tg_auditoria_excluir
AFTER DELETE ON usuarios_cnpj
FOR EACH ROW
BEGIN
    IF OLD.tipo_documento = 'CNPJ' THEN                                          -- ------> Só registra logs de clientes (CNPJ)
        INSERT INTO auditoria_usuarios (`ID do Usuário`, `Documento Afetado`, `Tipo Documento`, `Perfil do Usuário`, `Ação Realizada`, `Operador do Sistema`)
        VALUES (OLD.id, OLD.documento, OLD.tipo_documento, OLD.perfil, 'EXCLUSÃO DEFINITIVA DA CONTA', COALESCE(@usuario_sessao, USER()));
    END IF;
END$$
DELIMITER ;



-- <<<<<<<<<<<<<<<<<<<<< PARTE 13: TESTE PRÁTICO DO COFRE >>>>>>>>>>>>>>>>>>>>>>>>> 

/* CALL procedure_cadastrar_usuario_cnpj(
    '11444777000161', 'CNPJ', 'contato@empresa.com', 
    '$11111111111111111111111111111111111111111111111111111111111', 
    'Empresa Teste LTDA', 'Cliente', 'recXXXXXXXXXXXXXX', 'admin_ti@itr.com'
); */

/* CALL procedure_cadastrar_usuario_cnpj(
    '11144477735', 'CPF', 'funcionario@itr.com', 
    '$22222222222222222222222222222222222222222222222222222222222', 
    'João Silva', 'Funcionario', NULL, 'admin_ti@itr.com'
); */ 

/* CALL procedure_cadastrar_usuario_cnpj(
    '52998224725', 'CPF', 'ti@itr.com', 
    '$33333333333333333333333333333333333333333333333333333333333', 
    'Mateus Nascimento', 'Gerente_TI', NULL, 'admin_ti@itr.com'
); */ 


-- <<<<<<<<<<<<<<<<<<<<<<<<<< Parte 14: Limpeza de sessão (tanto para Logs quanto para tokens) >>>>>>>>>>>>>>>>>>>>>>> 
-- ------> Procedures de limpeza para manter o banco rápido e leve

-- LIMPEZA 1: Sessões expiradas
DELIMITER $$
CREATE PROCEDURE procedure_limpar_sessoes_expiradas()
BEGIN
    DELETE FROM sessoes_ativas
    WHERE expira_em < NOW()
       OR (revogada = TRUE AND criada_em < DATE_SUB(NOW(), INTERVAL 30 DAY));
END $$ 
DELIMITER ; 


-- LIMPEZA 2: Histórico de logins com mais de 3 meses 
DELIMITER $$
CREATE PROCEDURE procedure_limpar_historico_antigo()
BEGIN
    DELETE FROM historico_logins
    WHERE data_tentativa < DATE_SUB(NOW(), INTERVAL 3 MONTH);
END $$
DELIMITER ;


-- LIMPEZA 3: Auditoria com mais de 6 meses
DELIMITER $$
CREATE PROCEDURE procedure_limpar_auditoria_antiga() 
BEGIN
    DELETE FROM auditoria_usuarios
    WHERE `Data e Hora da Ação` < DATE_SUB(NOW(), INTERVAL 6 MONTH);
END $$
DELIMITER ;

-- LIMPEZA 4: Tokens de reset de senha expirados
DELIMITER $$
CREATE PROCEDURE procedure_limpar_tokens_reset()
BEGIN
    UPDATE usuarios_cnpj
    SET reset_token = NULL, reset_expires = NULL
    WHERE reset_expires IS NOT NULL AND reset_expires < NOW();
END $$
DELIMITER ; 


-- <<<<<<<<<<<<<<<<<<<<<<<< PARTE 15: EVENTOS AGENDADOS >>>>>>>>>>>>>>>>>>>>>>>>> 
-- ------> Executa as limpezas automaticamente em horários definidos

SET GLOBAL event_scheduler = ON;                                                  -- ------> Ativa o agendador automático do MySQL

CREATE EVENT IF NOT EXISTS evento_limpar_sessoes
ON SCHEDULE EVERY 1 HOUR
DO CALL procedure_limpar_sessoes_expiradas();



CREATE EVENT IF NOT EXISTS evento_limpar_historico
ON SCHEDULE EVERY 1 DAY 
STARTS (TIMESTAMP(CURRENT_DATE) + INTERVAL 27 HOUR)
DO CALL procedure_limpar_historico_antigo();


CREATE EVENT IF NOT EXISTS evento_limpar_auditoria
ON SCHEDULE EVERY 1 DAY
STARTS (TIMESTAMP(CURRENT_DATE) + INTERVAL 27 HOUR)
DO CALL procedure_limpar_auditoria_antiga();


CREATE EVENT IF NOT EXISTS evento_limpar_tokens
ON SCHEDULE EVERY 30 MINUTE
DO CALL procedure_limpar_tokens_reset();



-- <<<<<<<<<<<<<<<<<<<<< VISUALIZAÇÃO DOS RESULTADOS >>>>>>>>>>>>>>>>>>>>>>>>> 

SELECT id, documento, tipo_documento, email, nome_empresa, perfil, status_conta, data_exclusao FROM usuarios_cnpj;
SELECT * FROM permissoes_perfil;
SELECT * FROM auditoria_usuarios;

-- Novos Selects 
SELECT * FROM sessoes_ativas;
SELECT * FROM historico_logins; 
