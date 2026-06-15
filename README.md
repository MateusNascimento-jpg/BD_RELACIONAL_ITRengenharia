# ITR Engenharia - Banco de Dados para Gestão de Amostras

Modelagem de dados e arquitetura de tabelas desenvolvida para o ecossistema de controle de amostras, clientes e ensaios laboratoriais da ITR Engenharia. Este repositório concentra a inteligência relacional, regras de negócio e restrições de integridade que servirão de fundação para a futura API em Node.js e integração com o Airtable.

## Características da Arquitetura do Banco

* **Estrutura Relacional de Produção:** Modelagem focada no ciclo de vida laboratorial, estabelecendo vínculos precisos entre Amostras, Clientes e Ensaios Técnicos para evitar redundância de dados.
* **Consistência Dinâmica:** Tabelas projetadas estrategicamente para espelhar e validar os campos de seleção dinâmicos provenientes da API do Airtable, garantindo que o banco de dados local opere em perfeita sincronia com o ecossistema em nuvem.
* **Performance e Indexação para Busca:** Aplicação de índices estruturados (B-Tree) nas colunas de pesquisa frequente para viabilizar consultas e filtros em tempo real de forma instantânea, mitigando gargalos de processamento.
* **Segurança e Blindagem Nativa:** Implementação de restrições de validação direta no motor do banco, garantindo integridade absoluta nos registros das amostras antes mesmo do dado chegar à camada do servidor.

* © ITR Engenharia — uso interno 

