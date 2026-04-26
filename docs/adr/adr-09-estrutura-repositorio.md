# ADR-09: Estratégia de Versionamento do Repositório — O que Entra, O que Não Entra e a Estrutura Canônica de Diretórios

## Status

Proposta

> _Esta decisão foi tomada durante a fase de planejamento — nenhuma fase do projeto foi implementada. O status será revisado para `Aceita` após implementação e validação em ambiente real._

---

## Contexto

### O problema que um repositório público cria

Um repositório privado tem uma audiência conhecida e um propósito operacional claro: é a base de trabalho do projeto. Um repositório público de portfólio tem dois problemas adicionais que não existem no repositório privado.

O primeiro é de segurança: qualquer arquivo commitado fica acessível a qualquer pessoa com acesso à internet, incluindo o histórico de commits. Uma chave de service account GCP commitada acidentalmente continua exposta mesmo depois de removida do branch atual — ela existe no histórico. A proteção adequada não é remover o arquivo depois; é nunca commitá-lo.

O segundo é de percepção: a estrutura de diretórios de um repositório público é a primeira leitura que um recrutador ou engenheiro faz do projeto. Antes de abrir qualquer arquivo de código, o avaliador vê a lista de diretórios e arquivos na raiz. Um repositório onde o diretório `terraform/` está no mesmo nível que `__pycache__/` sinaliza descuido. Um repositório com `data/` na raiz cheio de CSVs sinaliza que o autor não separou artefatos de código de artefatos de dados. Ambos são ruídos que distraem da avaliação do trabalho técnico real.

### Os dois leitores do repositório

O repositório público tem dois leitores com expectativas distintas:

**Recrutador técnico** (primeiro leitor): lê o `README.md`, navega pela estrutura de diretórios, abre uma ADR ou um arquivo de DAG. Avalia em 5–10 minutos se o candidato demonstra maturidade de engenharia. O que sinaliza positivamente: estrutura limpa e intencional, `terraform/` com código HCL real, `docs/adr/` com decisões documentadas, `.github/` com workflows de CI/CD. O que sinaliza negativamente: diretórios de ferramentas de desenvolvimento, arquivos de credenciais, dados brutos, logs.

**Engenheiro avaliador** (segundo leitor): lê o código com atenção, revisa as ADRs, valida se as decisões fazem sentido. Avalia em 30–60 minutos se o raciocínio arquitetural é defensável. O que importa aqui não é a estrutura de diretórios — é a qualidade do código e das decisões. A estrutura do repositório deve estar resolvida antes que esse leitor apareça.

### A questão específica do `.claude/agents/`

O diretório `.claude/agents/` contém 9 arquivos Markdown com as especificações dos agentes de IA especializados criados com Claude Code para gerar as ADRs deste projeto. Esses agentes não são código do pipeline, não são documentação do sistema, não são configuração de infraestrutura. São scaffolding do processo de desenvolvimento — o equivalente funcional de scripts de geração de boilerplate que ajudaram a estruturar o projeto e que não pertencem ao resultado final.

A ADR-00 já documenta explicitamente que o projeto foi desenvolvido com Claude Code. A questão não é transparência — é o que pertence ao repositório público do pipeline.

Versionar os agentes cria um trade-off concreto entre dois valores:

- **Transparência de processo**: mostrar não apenas o resultado (as ADRs), mas o mecanismo que as gerou. Isso poderia ser lido como engenharia de prompts como competência demonstrável.
- **Clareza da narrativa do repositório**: o repositório conta a história do pipeline de dados — arquitetura, orquestração, transformações, infraestrutura. Os agentes contam a história do processo de planejamento. As duas histórias têm audiências parcialmente sobrepostas, mas o repositório público tem uma função primária: demonstrar o pipeline.

### Contexto adicional: o que o `.gitignore` atual cobre — e o que não cobre

O `.gitignore` atual do repositório já exclui corretamente os principais artefatos que não devem ser versionados: `*.tfstate`, `*.tfstate.backup`, `.terraform/`, arquivos de credenciais (`*.json` com exceção de `package.json`, `.env`, `*.pem`, `*.key`), dados (`*.csv`, `*.parquet`), artefatos Python (`__pycache__/`, `.venv/`, `venv/`), logs do Airflow e IDEs comuns (`.vscode/`, `.idea/`).

O que o `.gitignore` atual não exclui: o diretório `.claude/`. Essa omissão é uma lacuna que esta ADR resolve como consequência direta da decisão sobre versionar ou não os agentes.

---

## Decisão

### 1. O que versionar

Os seguintes artefatos pertencem ao repositório e são versionados:

| Artefato | Justificativa |
|----------|---------------|
| `docs/` | ADRs (ADR-00 a ADR-09 e futuras) e cronograma. São o registro permanente das decisões arquiteturais — parte central da narrativa do portfólio. |
| `src/` | Jobs PySpark de transformação (Bronze → Silver → Gold) e assertions de qualidade de dados (ADR-05). É o código de processamento do pipeline. **Este é o nome canônico do diretório** — qualquer referência informal a `spark_jobs/` em documentos de planejamento anteriores deve ser reconciliada com `src/` durante a implementação. `[VERIFICAR #19]` |
| `dags/` | DAGs do Airflow com TaskFlow API (ADR-01), incluindo a lógica de criação e destruição do cluster Dataproc efêmero (ADR-04). |
| `terraform/` | Código HCL que declara toda a infraestrutura GCP (ADR-08). Versionar o Terraform é parte do argumento de reproducibilidade — `git clone` + `terraform apply` deve ser suficiente para recriar o ambiente. |
| `.github/` | Workflows de GitHub Actions: `terraform fmt --check`, `terraform validate`, `terraform plan` com output publicado como comentário no PR (ADR-08). |
| `docker-compose.yml` | Configuração do ambiente Airflow na VM e2-medium (ADR-06). |
| `README.md` | Documentação de entrada do repositório: pré-requisitos de setup, ordem de execução, referências às ADRs. |
| `.gitignore` | O próprio arquivo de exclusões é artefato do repositório. |
| `.env.example` | Template de variáveis de ambiente com valores fictícios e sem credenciais reais. O arquivo `.env` com valores reais é excluído pelo `.gitignore`; o `.env.example` documenta quais variáveis o projeto espera — essencial para que qualquer pessoa que clone o repositório saiba o que configurar antes de executar o pipeline. |

### 2. O que não versionar

**Credenciais e segredos**

Arquivos de chave JSON de service account GCP, arquivos `.env` com variáveis de ambiente sensíveis e quaisquer credenciais de acesso. O `.gitignore` atual exclui `*.json` (com exceção de `package.json`), `.env` e variantes, `*.pem`, `*.key`, `*.p12` e o diretório `secrets/`. Essas exclusões são adequadas e não precisam de alteração.

Uma nota sobre Google Application Default Credentials locais (`~/.config/gcloud/`): por definição, ficam fora do repositório. Não há ação necessária no `.gitignore` para esse caso. Está documentado aqui para que o README do projeto oriente novos usuários sobre como configurar autenticação local.

**Estado do Terraform**

`terraform.tfstate` e `terraform.tfstate.backup` nunca entram no repositório, mesmo que o remote state em GCS esteja configurado conforme a ADR-08. Arquivos de state local gerados durante o bootstrap ou em execuções locais podem conter valores sensíveis de configuração de recursos GCP. O `.gitignore` atual já exclui `*.tfstate` e `*.tfstate.backup`.

O diretório `.terraform/` e arquivos `*.tfplan` também não entram: são artefatos de execução local gerados por `terraform init` e `terraform plan -out` respectivamente. Já excluídos pelo `.gitignore` atual via `**/.terraform/`.

**Dados**

Arquivos CSV da ANAC, arquivos Parquet e Delta locais gerados durante desenvolvimento ou testes não pertencem ao repositório. O pipeline processa dados via GCS (ADR-07) — os dados em si são artefatos de execução, não de código. O `.gitignore` atual exclui `*.csv`, `*.parquet`, `*.avro` e o diretório `data/`. As exclusões são adequadas.

**Artefatos de execução do Airflow**

Logs do Airflow (`logs/`), banco de dados SQLite local do Airflow (`airflow.db`), arquivos de configuração gerados (`airflow.cfg`, `webserver_config.py`, `standalone_admin_password.txt`). Todos já excluídos pelo `.gitignore` atual.

**Artefatos de runtime Python**

`__pycache__/`, `*.pyc`, `*.pyo`, `.pytest_cache/`, `.mypy_cache/`, diretórios de ambiente virtual (`.venv/`, `venv/`, `env/`). Já excluídos pelo `.gitignore` atual.

### 3. Decisão sobre `.claude/agents/` — não versionar

**Os agentes de IA do `.claude/agents/` não entram no repositório público.**

O diretório `.claude/` deve ser adicionado ao `.gitignore`. `[VERIFICAR]` — confirmar que essa entrada foi adicionada ao `.gitignore` antes de qualquer `git push` para o repositório público.

A justificativa não é ocultação — a ADR-00 já documenta explicitamente que o projeto foi desenvolvido com Claude Code. A justificativa é sobre o que o repositório público deve contar.

O repositório conta a história do pipeline de dados: arquitetura Medalhão, orquestração com Airflow, PySpark distribuído no Dataproc, Delta Lake, infraestrutura como código. Essa é a história relevante para o avaliador técnico. Os agentes contam uma história diferente — a história de como as ADRs foram geradas. Essas duas histórias não precisam coexistir no mesmo artefato público.

Há também uma razão de coerência estrutural: `.claude/` é um diretório de configuração de ferramenta de desenvolvimento, análogo ao `.vscode/` que já está excluído. A regra geral do projeto — artefatos de ferramentas de desenvolvimento não entram no repositório — se aplica ao `.claude/` pelo mesmo princípio que se aplica ao `.vscode/` e ao `**/.terraform/`.

O argumento em favor de versionar — demonstrar engenharia de prompts como competência — é real, mas tem uma premissa frágil: assume que o avaliador vai chegar ao `.claude/agents/`, entender o que são os arquivos, e interpretar a presença dos agentes como competência adicional em vez de levantar questões sobre autoria. A documentação em ADR-00 sobre o uso de Claude Code é o canal correto para essa transparência — não a estrutura de diretórios.

### 4. Estrutura canônica de diretórios

A estrutura que o repositório terá na raiz após o término da implementação:

```
anac-flight-pipeline/
├── .github/
│   └── workflows/          # terraform fmt, validate, plan — CI/CD no PR
├── dags/                   # DAGs do Airflow (TaskFlow API)
├── docs/
│   ├── adr/                # ADR-00 a ADR-09 (e futuras)
│   └── cronograma.md       # cronograma de implementação por fase
├── src/                    # jobs PySpark e assertions de qualidade de dados
├── terraform/              # código HCL — todos os recursos GCP do projeto
├── .gitignore              # exclusões do versionamento
├── docker-compose.yml      # configuração Airflow na VM e2-medium
└── README.md               # pré-requisitos, setup, ordem de execução
```

O que está ausente por decisão explícita:

- `.claude/` — não versionado (esta ADR)
- `data/` — dados ficam no GCS, não no repositório (ADR-07)
- `logs/` — artefato de execução, não de código
- `notebooks/` — nenhum notebook de análise exploratória pertence ao pipeline de produção; `.gitignore` já exclui `*.ipynb`

---

## Alternativas consideradas

### Versionar `.claude/agents/` como demonstração de engenharia de prompts

**O que seria**: incluir os 9 arquivos Markdown dos agentes especializados no repositório público, potencialmente com uma seção no README explicando o papel de cada agente na geração das ADRs.

**Por que foi rejeitado**: os agentes são scaffolding de processo de desenvolvimento, não artefatos do pipeline. Versionar ferramentas de desenvolvimento específicas de uma sessão de planejamento introduz ruído na narrativa do repositório — que deve ser sobre o pipeline, não sobre o processo de criação das ADRs. A transparência sobre o uso de Claude Code está adequadamente documentada na ADR-00, que é o lugar certo para esse contexto: uma decisão arquitetural que qualquer avaliador vai ler no fluxo normal de avaliação do projeto.

Há também um risco de percepção que a transparência da ADR-00 não carrega: encontrar 9 arquivos de agentes de IA em `.claude/agents/` pode gerar a pergunta "quem tomou essas decisões — o autor ou os agentes?", que a ADR-00 já antecipa e responde, mas em um contexto diferente. A ADR-00 faz essa contextualização narrativa corretamente. A presença dos arquivos de agentes no repositório, sem o contexto adequado, cria a dúvida antes de o avaliador chegar à ADR-00.

### Versionar parte do `.claude/` — apenas os agentes, sem a pasta `.claude/`

**O que seria**: copiar os arquivos Markdown dos agentes para um diretório `docs/agents/` ou similar, separando-os do diretório `.claude/` que é específico do Claude Code.

**Por que foi rejeitado**: a decisão sobre o que versionar não muda com a localização do arquivo. O problema não é que os agentes estão em `.claude/` — é que os agentes são scaffolding de processo de desenvolvimento. Movê-los para `docs/` não altera o que são. Criaria um diretório adicional que a estrutura canônica de `docs/` não contempla — ADRs e cronograma, não ferramentas de geração de ADRs.

### Versionar artefatos de dados para facilitar reprodução local

**O que seria**: incluir uma amostra representativa dos CSVs da ANAC no repositório para facilitar testes locais sem GCS.

**Por que foi rejeitado**: os dados da ANAC são distribuídos publicamente pelo portal da agência — não há necessidade de versioná-los, já que qualquer usuário pode baixá-los da fonte original. O pipeline tem uma task dedicada de download (ADR-07). Versionar dados brutos cria um repositório pesado sem vantagem funcional — o `git clone` carregaria arquivos CSV que o pipeline baixa de qualquer forma. Dados de amostra para testes unitários, se necessário, devem ser mínimos e representativos, não uma fatia do dataset real — e esse escopo cabe em `src/tests/fixtures/`, não na raiz do repositório.

---

## Consequências

### Positivas

**Segurança por estrutura**: o `.gitignore` exclui ativamente as categorias de arquivos sensíveis antes que qualquer `git add` inadvertido possa commitá-los. Credenciais de service account, `terraform.tfstate` e arquivos `.env` não entram no repositório — não porque o desenvolvedor está vigilante em cada commit, mas porque o `.gitignore` nega o commit automaticamente.

**Narrativa do repositório sem ruído**: a estrutura canônica de diretórios conta a história do pipeline de forma direta. `docs/adr/` com 9 ADRs, `terraform/` com código HCL, `dags/` com TaskFlow API, `src/` com PySpark, `.github/` com workflows de CI/CD — cada diretório justifica sua presença no contexto de um pipeline de engenharia de dados enterprise.

**Reproducibilidade verificável via `terraform apply`**: versionar o código Terraform (ADR-08) é o que torna a reproducibilidade do ambiente uma propriedade verificável, não uma afirmação no README. `git clone` + `terraform apply` + `docker compose up` produz um ambiente funcionalmente idêntico ao do autor.

**Entrada no repositório orientada ao avaliador**: um recrutador ou engenheiro que abre o repositório pela primeira vez encontra exatamente o que precisa para avaliar o trabalho — não logs, não dados brutos, não artefatos de ferramentas de desenvolvimento.

### Negativas

**Decisão de não versionar `.claude/agents/` é irreversível no histórico público**: se a decisão for revertida depois do repositório se tornar público, os agentes vão para o repositório a partir daquele ponto, mas não estarão no histórico anterior. Não é um problema operacional — é apenas o comportamento normal do git. A decisão deve ser tomada antes do primeiro push público.

**Ausência de dados locais exige GCS para qualquer teste end-to-end**: a decisão de não versionar dados significa que testar o pipeline localmente requer acesso ao GCS e credenciais GCP configuradas. Isso é coerente com a arquitetura do projeto (pipeline distribuído sobre GCS, não sobre filesystem local), mas é um pré-requisito não trivial para novos contribuidores ou para o próprio autor em uma máquina nova. O README deve documentar esse requisito explicitamente.

**O `.gitignore` atual não exclui `.claude/`**: a decisão desta ADR implica adicionar `.claude/` ao `.gitignore`. `[VERIFICAR]` — confirmar que essa entrada foi adicionada ao `.gitignore` do repositório antes do primeiro `git push` para o repositório público. A omissão atual não gera risco imediato (os arquivos de agentes não são sensíveis), mas é uma inconsistência com a decisão tomada aqui.

---

## Dependências

### Esta ADR depende de

| ADR | Dependência |
|-----|-------------|
| ADR-00 | O objetivo de portfólio e a documentação do uso de Claude Code definem o contexto de percepção do recrutador — fator central na decisão sobre `.claude/agents/`. A decisão de não versionar os agentes é coerente com, e não substitui, a transparência documentada na ADR-00. |
| ADR-08 | Define que o Terraform state remoto fica no GCS e que `terraform.tfstate` nunca vai para o repositório. Esta ADR referencia diretamente essa decisão ao confirmar o que não entra no versionamento. O ponto `[VERIFICAR #17]` da ADR-00 (confirmar que `*.tfstate` está no `.gitignore`) já está resolvido pelo `.gitignore` atual do projeto. |
| ADR-06 | Define que o Airflow roda via Docker Compose na VM e2-medium. Esta ADR inclui `docker-compose.yml` na lista de artefatos versionados com base nessa decisão. |
| ADR-07 | Define que os dados são armazenados no GCS, não localmente. Esta ADR fundamenta a decisão de não versionar dados brutos da ANAC com base na arquitetura do pipeline. |

### ADRs que dependem desta

Esta é a última ADR do conjunto de planejamento. Nenhuma decisão arquitetural subsequente pressupõe a ADR-09 para seu racional interno. A ADR-09 documenta o envelope que contém todas as demais.

---

## Referências

- ADR-00: Contexto Global e Constraints do Projeto (inclui Checklist de Pontos `[VERIFICAR]`)
- ADR-06: Deployment do Airflow — VM Compute Engine e2-medium com Docker Compose
- ADR-07: Arquitetura de Camadas do Pipeline — Padrão Medalhão (Bronze/Silver/Gold)
- ADR-08: Provisionamento de Infraestrutura — Terraform como Única Fonte de Verdade para Recursos GCP
- [Git — gitignore documentation](https://git-scm.com/docs/gitignore)
- [GitHub — Managing large files](https://docs.github.com/en/repositories/working-with-files/managing-large-files)
