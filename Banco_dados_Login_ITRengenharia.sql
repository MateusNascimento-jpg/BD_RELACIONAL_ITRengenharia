DROP DATABASE IF EXISTS ITRengenhariaLOGIN; 
CREATE DATABASE ITRengenhariaLOGIN;
USE ITRengenhariaLOGIN;


-- <<<<<<<<<<<<<<<<<<< PARTE 1: TABELA PRINCIPAL DE USUÁRIOS >>>>>>>>>>>>>>>>>>

CREATE TABLE usuarios_cnpj (
    id                  INT AUTO_INCREMENT PRIMARY KEY,
    
    documento           VARCHAR(14)  NOT NULL UNIQUE,                                               
    tipo_documento      ENUM('CPF', 'CNPJ') NOT NULL,                                               
    email               VARCHAR(150) NULL UNIQUE,    
    senha_hash          VARCHAR(255) NOT NULL,
    
    nome_empresa        VARCHAR(200) NULL,                                                          -- ------> Nome/razão social da empresa (ou nome do funcionário)
    perfil              ENUM('Cliente', 'Funcionario', 'Gerente_TI', 'Diretor') DEFAULT 'Cliente',  -- ------> Define o nível de acesso do usuário
    airtable_client_id  VARCHAR(50)  NULL,                                                          -- ------> Vincula o usuário ao cliente do Airtable
    reset_token         VARCHAR(255) NULL,                                                          -- ------> Token gerado quando o usuário esquece a senha
    reset_expires       TIMESTAMP    NULL,                                                          -- ------> Validade do token de recuperação (1 hora; configuração no backend)
    ultimo_login        TIMESTAMP    NULL,                                                          -- ------> Marca a última vez que o usuário entrou no sistema
    
    tentativas_login    INT          DEFAULT 0,                                                     -- ------> Conta tentativas de login erradas seguidas
    bloqueado_ate       TIMESTAMP    NULL,                                                          -- ------> Data até a qual a conta está temporariamente bloqueada

    status_conta        ENUM('Ativo', 'Inativo', 'Bloqueado') DEFAULT 'Ativo',
    data_cadastro       TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    ultima_atualizacao  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    -- Restrições de Validação (Robustez de Dados)
    CONSTRAINT chk_documento_tamanho CHECK (LENGTH(documento) IN (11, 14)),                         -- ------> Garante 11 (CPF) ou 14 (CNPJ) dígitos
    CONSTRAINT chk_documento_numerico CHECK (documento REGEXP '^[0-9]+$'),                          -- ------> Garante que só tem números (sem máscara de difrenciação) 
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
-- ------> Tabela nova que define o que cada perfil pode fazer no sistema

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


-- <<<<<<<<<<<<<<<<<<<<<<<< PARTE 4: FUNÇÃO PARA VALIDAR CPF >>>>>>>>>>>>>>>>>>>>>>>>>
-- ------> Função nova que valida matematicamente os dígitos verificadores do CPF

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
    
    -- ------> Verifica se tem 11 dígitos
    IF LENGTH(p_cpf) <> 11 THEN RETURN FALSE; END IF; 
    
    -- ------> Rejeita CPFs com todos os dígitos iguais (111.111.111-11, 222.222.222-22, etc.)
    IF p_cpf REGEXP '^([0-9])\\1{10}$' THEN RETURN FALSE; END IF;
    
    -- ------> Calcula o primeiro dígito verificador
    WHILE i <= 9 DO
        SET soma = soma + (CAST(SUBSTRING(p_cpf, i, 1) AS UNSIGNED) * (11 - i));
        SET i = i + 1;
    END WHILE;
    SET resto = soma % 11;
    SET digito1 = IF(resto < 2, 0, 11 - resto);
    
    IF digito1 <> CAST(SUBSTRING(p_cpf, 10, 1) AS UNSIGNED) THEN RETURN FALSE; END IF; 
    
    -- ------> Calcula o segundo dígito verificador
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


-- <<<<<<<<<<<<<<<<<<<<<<<< PARTE 5: FUNÇÃO PARA VALIDAR CNPJ >>>>>>>>>>>>>>>>>>>>>>>>>
-- ------> Função nova que valida matematicamente os dígitos verificadores do CNPJ

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
    
    -- ------> Verifica se tem 14 dígitos
    IF LENGTH(p_cnpj) <> 14 THEN RETURN FALSE; END IF;
    
    -- ------> Rejeita CNPJs com todos os dígitos iguais
    IF p_cnpj REGEXP '^([0-9])\\1{13}$' THEN RETURN FALSE; END IF; 
    
    -- ------> Calcula o primeiro dígito verificador
    WHILE i <= 12 DO
        SET soma = soma + (CAST(SUBSTRING(p_cnpj, i, 1) AS UNSIGNED) * peso);
        SET peso = IF(peso = 2, 9, peso - 1);
        SET i = i + 1;
    END WHILE;
    SET resto = soma % 11;
    SET digito1 = IF(resto < 2, 0, 11 - resto);
    
    IF digito1 <> CAST(SUBSTRING(p_cnpj, 13, 1) AS UNSIGNED) THEN RETURN FALSE; END IF;
    
    -- ------> Calcula o segundo dígito verificador
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


-- <<<<<<<<<<<<<<<<<<<<<<<< PARTE 6: PROCEDURE DE CADASTRO >>>>>>>>>>>>>>>>>>>>>>>>> 

DELIMITER $$

CREATE PROCEDURE procedure_cadastrar_usuario_cnpj(
    IN p_documento VARCHAR(14),                                                       -- ------> CPF ou CNPJ apenas com números
    IN p_tipo_documento ENUM('CPF', 'CNPJ'),                                          -- ------> Tipo do documento
    IN p_email VARCHAR(150), 
    IN p_senha_hash VARCHAR(255),
    IN p_nome_empresa VARCHAR(200),                                                   -- ------> Nome da empresa ou do funcionário
    IN p_perfil ENUM('Cliente','Funcionario','Gerente_TI','Diretor'),                 -- ------> Perfil de acesso
    IN p_airtable_client_id VARCHAR(50),                                              -- ------> ID do cliente no Airtable (NULL para funcionários)
    IN p_operador VARCHAR(100)
)
BEGIN
    -- ------> Captura erro de duplicidade (CPF/CNPJ ou email já cadastrado)
    DECLARE EXIT HANDLER FOR 1062
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERRO: Este CPF/CNPJ ou E-mail já encontra-se cadastrado no sistema.';
    END;

    -- Captura qualquer outro erro inesperado do banco
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERRO: Ocorreu uma falha interna ao tentar processar o cadastro.';
    END;

    -- ------> Valida matematicamente o CPF antes de cadastrar
    IF p_tipo_documento = 'CPF' AND NOT fn_validar_cpf(p_documento) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERRO: CPF inválido. Verifique os dígitos.';
    END IF;
    
    -- ------> Valida matematicamente o CNPJ antes de cadastrar
    IF p_tipo_documento = 'CNPJ' AND NOT fn_validar_cnpj(p_documento) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERRO: CNPJ inválido. Verifique os dígitos.';
    END IF;

    SET @usuario_sessao = p_operador;

    START TRANSACTION;
        -- ------> INSERT atualizado com documento e tipo_documento separados
        INSERT INTO usuarios_cnpj (documento, tipo_documento, email, senha_hash, nome_empresa, perfil, airtable_client_id) 
        VALUES (p_documento, p_tipo_documento, p_email, p_senha_hash, p_nome_empresa, COALESCE(p_perfil, 'Cliente'), p_airtable_client_id);
    COMMIT;
END $$

DELIMITER ;


-- <<<<<<<<<<<<<<<<<<<<<<<< PARTE 7: PROCEDURE DE LOGIN COM BLOQUEIO >>>>>>>>>>>>>>>>>>>>>>>>> 

-- ------> Procedure de login que controla tentativas erradas e bloqueio temporário

DELIMITER $$

CREATE PROCEDURE procedure_registrar_login(
    IN p_documento VARCHAR(14)                                                        -- ------> CPF ou CNPJ apenas com números
)
BEGIN
    -- ------> Atualiza a data do último login e zera tentativas (login bem-sucedido)
    UPDATE usuarios_cnpj 
    SET ultimo_login = CURRENT_TIMESTAMP,
        tentativas_login = 0,
        bloqueado_ate = NULL
    WHERE documento = p_documento AND status_conta = 'Ativo';
    
    -- ------> Retorna os dados do usuário para o Node.js criar a sessão
    SELECT id, documento, tipo_documento, email, nome_empresa, perfil, airtable_client_id, status_conta
    FROM usuarios_cnpj 
    WHERE documento = p_documento;
END $$

DELIMITER ;


-- <<<<<<<<<<<<<<<<<<<<<<<< PARTE 8: PROCEDURE DE TENTATIVA ERRADA >>>>>>>>>>>>>>>>>>>>>>>>> 
-- ------> Procedure nova que incrementa tentativas erradas e bloqueia após 5 falhas

DELIMITER $$

CREATE PROCEDURE procedure_login_falhou(
    IN p_documento VARCHAR(14)                                                        -- ------> CPF ou CNPJ que tentou logar
)
BEGIN
    DECLARE v_tentativas INT DEFAULT 0;
    
    -- ------> Busca quantas tentativas erradas já houve
    SELECT tentativas_login INTO v_tentativas
    FROM usuarios_cnpj
    WHERE documento = p_documento;
    
    -- ------> Se passou de 5 tentativas, bloqueia por 15 minutos
    IF v_tentativas + 1 >= 5 THEN
        UPDATE usuarios_cnpj
        SET tentativas_login = v_tentativas + 1,
            bloqueado_ate = DATE_ADD(NOW(), INTERVAL 15 MINUTE)
        WHERE documento = p_documento;
    ELSE
        -- ------> Apenas incrementa o contador
        UPDATE usuarios_cnpj
        SET tentativas_login = v_tentativas + 1
        WHERE documento = p_documento;
    END IF;
    
    -- ------> Retorna info para o backend mostrar mensagem adequada
    SELECT tentativas_login, bloqueado_ate
    FROM usuarios_cnpj 
    WHERE documento = p_documento;
END $$

DELIMITER ;


-- <<<<<<<<<<<<<<<<<<<<<<<<<< PARTE 9: TRIGGERS AUTOMÁTICOS >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 

-- Trigger A: Monitora novos cadastros

DELIMITER $$
CREATE TRIGGER tg_auditoria_inserir
AFTER INSERT ON usuarios_cnpj
FOR EACH ROW
BEGIN
    -- ------> INSERT do log atualizado para registrar documento, tipo e perfil
    INSERT INTO auditoria_usuarios (`ID do Usuário`, `Documento Afetado`, `Tipo Documento`, `Perfil do Usuário`, `Ação Realizada`, `Operador do Sistema`)
    VALUES (NEW.id, NEW.documento, NEW.tipo_documento, NEW.perfil, 'CADASTRO DE USUÁRIO', COALESCE(@usuario_sessao, USER()));
END$$
DELIMITER ;


-- Trigger B: Monitora atualizações e trocas de status
 
DELIMITER $$
CREATE TRIGGER tg_auditoria_atualizar
AFTER UPDATE ON usuarios_cnpj
FOR EACH ROW
BEGIN
    -- ------> Trigger ampliado: detecta mudanças de status, perfil, vínculo Airtable ou bloqueio
    INSERT INTO auditoria_usuarios (`ID do Usuário`, `Documento Afetado`, `Tipo Documento`, `Perfil do Usuário`, `Ação Realizada`, `Operador do Sistema`)
    VALUES (
        NEW.id, 
        NEW.documento,
        NEW.tipo_documento,
        NEW.perfil,
        CASE 
            WHEN OLD.status_conta <> NEW.status_conta THEN CONCAT('STATUS: ', OLD.status_conta, ' -> ', NEW.status_conta)
            WHEN OLD.perfil <> NEW.perfil THEN CONCAT('PERFIL: ', OLD.perfil, ' -> ', NEW.perfil)
            WHEN COALESCE(OLD.airtable_client_id,'') <> COALESCE(NEW.airtable_client_id,'') THEN 'VÍNCULO AIRTABLE ATUALIZADO'
            WHEN NEW.bloqueado_ate IS NOT NULL AND OLD.bloqueado_ate IS NULL THEN 'CONTA BLOQUEADA POR EXCESSO DE TENTATIVAS'
            ELSE 'ATUALIZAÇÃO DE DADOS'
        END,
        COALESCE(@usuario_sessao, USER())
    );
END$$
DELIMITER ;


-- Trigger C: Monitora se alguém deletar uma conta do sistema

DELIMITER $$
CREATE TRIGGER tg_auditoria_excluir
AFTER DELETE ON usuarios_cnpj
FOR EACH ROW
BEGIN
    -- ------> INSERT do log atualizado para registrar documento, tipo e perfil do usuário deletado
    INSERT INTO auditoria_usuarios (`ID do Usuário`, `Documento Afetado`, `Tipo Documento`, `Perfil do Usuário`, `Ação Realizada`, `Operador do Sistema`)
    VALUES (OLD.id, OLD.documento, OLD.tipo_documento, OLD.perfil, 'EXCLUSÃO DEFINITIVA DA CONTA', COALESCE(@usuario_sessao, USER()));
END$$
DELIMITER ;



-- <<<<<<<<<<<<<<<<<<<<< PARTE 10: TESTE PRÁTICO DO COFRE >>>>>>>>>>>>>>>>>>>>>>>>> 

-- 1. Cadastra um cliente (com CNPJ válido)
CALL procedure_cadastrar_usuario_cnpj(
    '11444777000161',                -- ------> CNPJ válido (apenas números)
    'CNPJ',                          -- ------> Tipo do documento
    'contato@empresa.com', 
    '$11111111111111111111111111111111111111111111111111111111111', 
    'Empresa Teste LTDA',
    'Cliente',
    'recXXXXXXXXXXXXXX',
    'admin_ti@itr.com'
); 

-- 2. Cadastra um funcionário (com CPF válido)
CALL procedure_cadastrar_usuario_cnpj(
    '11144477735',                   -- ------> CPF válido (apenas números)
    'CPF',                           -- ------> Tipo do documento
    'funcionario@itr.com', 
    '$22222222222222222222222222222222222222222222222222222222222', 
    'João Silva',
    'Funcionario',
    NULL,
    'admin_ti@itr.com'
);

-- 3. Cadastra o gerente de TI (com CPF válido)
CALL procedure_cadastrar_usuario_cnpj(
    '52998224725',                   -- ------> CPF válido
    'CPF',
    'ti@itr.com', 
    '$33333333333333333333333333333333333333333333333333333333333', 
    'Mateus Nascimento',
    'Gerente_TI',
    NULL,
    'admin_ti@itr.com'
);


-- <<<<<<<<<<<<<<<<<<<<< VISUALIZAÇÃO DOS RESULTADOS >>>>>>>>>>>>>>>>>>>>>>>>> 

-- CONSULTA 1: Lista todos os usuários
SELECT id, documento, tipo_documento, email, nome_empresa, perfil, airtable_client_id, status_conta, tentativas_login, bloqueado_ate FROM usuarios_cnpj;

-- CONSULTA 2: Mostra a tabela de permissões por perfil
SELECT * FROM permissoes_perfil;

-- CONSULTA 3: Mostra todo o histórico de auditoria
SELECT * FROM auditoria_usuarios;




