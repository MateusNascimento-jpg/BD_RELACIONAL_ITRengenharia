const express = require('express');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const pool = require('./db'); // Puxa a conexão do MySQL
require('dotenv').config();

const path = require('path');
const app = express();

// Funções do Airtable (inclui urlRelatorioAprovado para o download do PDF)
const { buscarTrabalhosDoCliente, buscarClientePorCnpj, urlRelatorioAprovado } = require('./airtable');

// Permite que o servidor entenda dados em formato JSON (enviados pelas telas)
app.use(express.json());

// Serve os arquivos HTML/CSS/JS da pasta "public"
// Assim http://localhost:3000/login.html abre a tela de login
app.use(express.static(path.join(__dirname, 'public')));

// ==================== FUNÇÃO AUXILIAR ====================
// Remove tudo que não for número do documento (pontos, traços, barras)
function limparDocumento(doc) {
    return String(doc || '').replace(/\D/g, '');
}

// ==================== ROTA DE TESTE ====================
app.get('/status', (req, res) => {
    res.json({ status: "Online", projeto: "ITR Engenharia Login" });
});

// ==================== ROTA: CADASTRO ====================
// CADASTRO PÚBLICO DE CLIENTE
// Regras: só aceita CNPJ; o CNPJ precisa existir na tabela Clientes do Airtable
// (trava de CNPJ); o perfil e o vínculo (airtable_client_id) são definidos pelo
// SERVIDOR, nunca pelo que vem do navegador.
app.post('/cadastro', async (req, res) => {
    try {
        let { documento, email, senha } = req.body;
        documento = limparDocumento(documento || ''); // só números

        // 1. Porta pública é só para CLIENTE (CNPJ = 14 dígitos)
        if (documento.length === 11) {
            return res.status(403).json({
                sucesso: false,
                erro: 'Funcionários devem solicitar acesso ao administrador.'
            });
        }
        if (documento.length !== 14) {
            return res.status(400).json({
                sucesso: false,
                erro: 'CNPJ inválido. Digite os 14 números do CNPJ.'
            });
        }
        if (!email || !senha) {
            return res.status(400).json({ sucesso: false, erro: 'Informe e-mail e senha.' });
        }

        // 2. Trava de CNPJ: tem que ser um cliente que já existe no Airtable
        const cliente = await buscarClientePorCnpj(documento);
        if (!cliente) {
            return res.status(404).json({
                sucesso: false,
                erro: 'CNPJ não encontrado em nossa base de clientes.'
            });
        }

        // 3. Cria a conta já vinculada. perfil e vínculo vêm do servidor.
        const senha_hash = await bcrypt.hash(senha, 10);
        const sql = 'CALL procedure_cadastrar_usuario_cnpj(?, ?, ?, ?, ?, ?, ?, ?)';
        await pool.query(sql, [
            documento,        // p_documento
            'CNPJ',           // p_tipo_documento
            email,            // p_email
            senha_hash,       // p_senha (hash)
            cliente.nome,     // p_nome_empresa (puxado do Airtable)
            'Cliente',        // p_perfil (sempre Cliente nesta porta)
            cliente.id,       // p_airtable_client_id (vínculo automático)
            'AUTOCADASTRO'    // p_operador
        ]);

        return res.status(201).json({
            sucesso: true,
            mensagem: 'Conta criada com sucesso! Já pode fazer login.'
        });
    } catch (error) {
        return res.status(400).json({ sucesso: false, erro: error.message });
    }
});

// ==================== ROTA: LOGIN ====================
app.post('/login', async (req, res) => {
    let { documento, senha } = req.body;

    try {
        documento = limparDocumento(documento);

        if (!documento || !senha) {
            return res.status(400).json({ sucesso: false, erro: "Informe documento e senha." });
        }

        // Busca o usuário pelo documento (apenas contas ativas)
        const [linhas] = await pool.query(
            'SELECT id, documento, senha_hash, perfil, airtable_client_id, nome_empresa, status_conta FROM usuarios_cnpj WHERE documento = ? AND data_exclusao IS NULL',
            [documento]
        );

        // Mensagem genérica de propósito (não revela se o documento existe)
        if (linhas.length === 0) {
            return res.status(401).json({ sucesso: false, erro: "Documento ou senha inválidos." });
        }

        const usuario = linhas[0];

        if (usuario.status_conta !== 'Ativo') {
            return res.status(403).json({ sucesso: false, erro: "Conta inativa ou bloqueada." });
        }

        // Confere a senha contra o hash salvo
        const senhaConfere = await bcrypt.compare(senha, usuario.senha_hash);
        if (!senhaConfere) {
            return res.status(401).json({ sucesso: false, erro: "Documento ou senha inválidos." });
        }

        // Gera o token JWT com os dados que as outras rotas vão usar
        const token = jwt.sign(
            {
                id: usuario.id,
                perfil: usuario.perfil,
                airtable_client_id: usuario.airtable_client_id
            },
            process.env.JWT_SECRET,
            { expiresIn: '8h' }
        );

        // Atualiza o último login
        await pool.query('UPDATE usuarios_cnpj SET ultimo_login = NOW(), tentativas_login = 0 WHERE id = ?', [usuario.id]);

        return res.json({
            sucesso: true,
            token: token,
            usuario: {
                perfil: usuario.perfil,
                nome_empresa: usuario.nome_empresa
            }
        });
    } catch (error) {
        return res.status(500).json({ sucesso: false, erro: error.message });
    }
});

// ==================== MIDDLEWARE: AUTENTICAÇÃO COM BASE NOS HEADERS ====================
// Coloque este "porteiro" antes de qualquer rota que precise de login.
function autenticado(req, res, next) {
    const header = req.headers['authorization'];
    const token = header && header.split(' ')[1]; // formato: "Bearer TOKEN"

    if (!token) {
        return res.status(401).json({ sucesso: false, erro: "Token não enviado." });
    }

    jwt.verify(token, process.env.JWT_SECRET, (err, dados) => {
        if (err) {
            return res.status(403).json({ sucesso: false, erro: "Token inválido ou expirado." });
        }
        req.usuario = dados; // disponibiliza id, perfil e airtable_client_id nas rotas
        next();
    });
}

// ==================== ROTA PROTEGIDA DE TESTE ====================
// Só responde se o token for válido. Bom para testar o login.
app.get('/perfil', autenticado, (req, res) => {
    res.json({ sucesso: true, usuario: req.usuario });
});

// ==================== ROTA: MEUS DADOS (Airtable) ====================
app.get('/api/meus-dados', autenticado, async (req, res) => {
    try {
        const recordId = req.usuario.airtable_client_id;

        if (!recordId) {
            return res.status(400).json({ sucesso: false, erro: "Usuário sem cliente vinculado." });
        }

        // offset = cursor da pagina seguinte (vem da resposta anterior do Airtable).
        // modo = "recente" (padrao: ultimos 3 meses + em andamento) ou "todos" (historico).
        const offset = req.query.offset || null;
        const modo = req.query.modo === 'todos' ? 'todos' : 'recente';

        const dados = await buscarTrabalhosDoCliente(recordId, offset, modo);
        return res.json({ sucesso: true, ...dados });
    } catch (error) {
        return res.status(500).json({ sucesso: false, erro: error.message });
    }
});

// ==================== ROTA: BAIXAR RELATÓRIO APROVADO ====================
// O cliente clica em "Baixar relatório" -> cai aqui -> buscamos uma URL nova
// do PDF aprovado no Airtable e redirecionamos. Assim nunca dá "link quebrado"
// (os links de anexo do Airtable expiram com o tempo).
app.get('/api/relatorio/:id', autenticado, async (req, res) => {
    try {
        const recordIdTrabalho = req.params.id;

        const arquivo = await urlRelatorioAprovado(recordIdTrabalho);
        if (!arquivo) {
            return res.status(404).json({ sucesso: false, erro: 'Relatório não disponível.' });
        }

        // Redireciona direto para a URL fresca do PDF (abre no navegador / baixa de lá).
        return res.redirect(arquivo.url);
    } catch (error) {
        return res.status(500).json({ sucesso: false, erro: error.message });
    }
});

// ==================== INICIAR SERVIDOR RODANDO NA MÁQUINA E PORTA PADRÃO ====================
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log(`Servidor backend da ITR rodando na porta ${PORT}`);
});