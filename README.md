# ITR Engenharia - Sistema de Gestão de Amostras

Plataforma corporativa web desenvolvida para o gerenciamento centralizado e controle de amostras laboratoriais da ITR Engenharia. O sistema atua como uma camada inteligente de integração (Middleware) entre a interface operacional e o ecossistema de bancos de dados do Airtable, garantindo consistência, performance e segurança no fluxo de ensaios técnicos.

##  Características Principais

* **Arquitetura de Integração Dinâmica:** Consumo centralizado via API do Airtable utilizando Axios, permitindo que campos de seleção, parâmetros de ensaios e dados de clientes sejam sincronizados e renderizados em tempo real na interface sem necessidade de reload.
* **Operações CRUD Otimizadas:** Controle total sobre o ciclo de vida das Amostras, Clientes e Ensaios, apoiado por um motor de busca indexado em tempo real que acelera a localização de registros laboratoriais.
* **Segurança e Isolamento de Credenciais:** Arquitetura de servidor que blinda os tokens de autenticação da API no ambiente do back-end utilizando variáveis seguras (`dotenv`), impedindo a exposição de chaves privadas no navegador do cliente (Client-Side).
* **Stack Modular e Leve:** Interface construída em HTML5 e JavaScript nativo para máxima velocidade, acoplada a um servidor robusto em Node.js com Express para gerenciamento eficiente de rotas HTTP e payloads.

* © ITR Engenharia — uso interno 

