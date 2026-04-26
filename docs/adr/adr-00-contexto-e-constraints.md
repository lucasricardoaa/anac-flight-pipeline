# ADR-00: Contexto Global e Constraints do Projeto

## Status

Proposta

> _Esta decisão foi tomada durante a fase de planejamento — nenhuma fase do projeto foi implementada. O status será revisado para `Aceita` após implementação e validação em ambiente real._

---

## Contexto

### O que é este projeto

Pipeline de dados batch que ingere, transforma e agrega estatísticas de transporte aéreo doméstico brasileiro publicadas pela ANAC (Agência Nacional de Aviação Civil). Os dados são disponibilizados mensalmente em formato CSV e processados em uma arquitetura Medalhão (Bronze/Silver/Gold) sobre Google Cloud Storage, com PySpark rodando em cluster Dataproc efêmero orquestrado por Apache Airflow.

### Motivador primário: objetivo de aprendizado

Este projeto existe para aprender PySpark e Apache Airflow de forma substantiva — não superficial. O dataset da ANAC é o pretexto. O objetivo real é operar essas ferramentas com a profundidade necessária para uma vaga de Engenheiro de Dados Pleno no mercado brasileiro.

Esse motivador primário tem consequências diretas nas decisões técnicas: quando havia alternativas tecnicamente mais simples para resolver o problema de dados (pandas + Parquet puro + cron, por exemplo), elas foram rejeitadas em favor de ferramentas com presença em JDs de vagas enterprise. Não porque pandas e Parquet sejam inadequados para o volume de dados da ANAC — mas porque aprender a operá-los não atende ao objetivo declarado.

### Público-alvo do portfólio

Recrutadores e engenheiros avaliando candidatos para vagas de Engenheiro de Dados Pleno no Brasil. O mercado brasileiro de vagas Pleno tem convergência clara em torno de: Apache Airflow, Apache Spark / PySpark, GCP ou AWS, e algum `open table format` (Delta Lake, Iceberg ou Hudi). Esse contexto influenciou diretamente quais tecnologias foram priorizadas:

- **Airflow** sobre Prefect ou Dagster — maior presença em vagas enterprise no Brasil
- **Delta Lake** sobre Parquet puro — demonstra conhecimento de `open table format` e operações ACID
- **Dataproc** sobre PySpark em modo local — demonstra Spark distribuído real, não apenas a API

### Restrição financeira como constraint não-funcional de primeira ordem

O projeto opera sobre o `free trial` do GCP com **$300 em créditos**. Esse número não é uma limitação a esconder — é um constraint de projeto que determinou várias decisões de infraestrutura:

- Cluster Dataproc efêmero em vez de permanente (~$200/mês parado para e2-standard-2 × 2 workers)
- Airflow em VM e2-medium com Docker Compose em vez de Cloud Composer (~$300/mês)
- Cluster efêmero com estratégia de proteção contra `cluster órfão` para evitar consumo acidental de créditos

Decisões que parecem subótimas em produção — `cold start` de 3–5 minutos por execução, ausência de alta disponibilidade no Airflow, VM single-node — são deliberadas e otimizadas para o contexto de portfólio + aprendizado + constraint de custo. Sem esse contexto documentado, um leitor externo interpreta essas escolhas como limitações técnicas do autor.

### Status no momento da documentação

Nenhuma fase do projeto foi implementada. Esta ADR e todas as ADRs de ADR-01 a ADR-08 documentam decisões tomadas durante a **fase de planejamento**. O código ainda não existe. Esse status é informação relevante para o leitor calibrar o que está avaliando: são decisões de arquitetura, não decisões validadas por execução em produção.

### Modo de desenvolvimento

O projeto foi desenvolvido com Claude Code — ferramenta de engenharia assistida por IA da Anthropic — incluindo a estruturação de decisões arquiteturais e a redação das ADRs. Essa informação contextualiza o processo de tomada de decisão: as ADRs documentam raciocínio arquitetural deliberado, não convenções geradas automaticamente.

---

## Decisão

Formalizar os constraints globais e o contexto de uso do projeto em uma ADR fundacional, que serve de âncora para todas as decisões específicas de ADR-01 a ADR-08.

A decisão central documentada aqui é que **este projeto é otimizado para três objetivos simultâneos e parcialmente conflitantes**: aprendizado substantivo de PySpark e Airflow, demonstração de stack enterprise para o mercado brasileiro de vagas Pleno, e viabilidade financeira dentro do `free trial` GCP de $300. Toda decisão técnica subseqüente é avaliada contra esses três objetivos, nessa ordem de prioridade.

---

## Alternativas consideradas

Esta seção, nas ADRs de ADR-01 a ADR-08, documenta alternativas técnicas rejeitadas para cada componente. Na ADR-00, a questão relevante é diferente: **por que este projeto requer uma ADR fundacional?**

A resposta está na natureza das decisões que seguem. Cluster Dataproc efêmero com `cold start` de 3–5 minutos é uma escolha que qualquer engenheiro experiente questionaria ao revisar o projeto — em produção, essa latência seria inaceitável para a maioria dos casos de uso. Airflow em VM e2-medium sem alta disponibilidade é outra escolha que seria reprovada em uma revisão de arquitetura enterprise. Cloud Composer rejeitado não por decisão técnica, mas porque seu custo equivale ao orçamento total do projeto.

Sem uma ADR que formalize os constraints globais, cada uma dessas decisões parece um erro de engenharia isolado. Com a ADR-00, elas passam a ser o que são: decisões conscientes, otimizadas para o contexto correto.

Projetos com stack óbvio e decisões sem trade-offs significativos não precisam de ADR-00. Este projeto tem decisões que seriam incompreensíveis sem o contexto global formalizado. Daí a existência deste documento.

---

## Consequências

### Positivas

- Decisões aparentemente subótimas em ADR-03 (Dataproc efêmero), ADR-04 (ciclo de vida do cluster), ADR-06 (Airflow em VM single-node) passam a ter âncora explícita nesta ADR, eliminando ambiguidade para o leitor externo.
- O constraint financeiro de $300 é tratado como dado de projeto, não como desculpa — o que demonstra maturidade de planejamento.
- O objetivo de aprendizado é documentado sem constrangimento, o que é coerente: vagas de Pleno no Brasil valorizam candidatos que sabem articular por que escolheram uma tecnologia, não apenas que a escolheram.
- A transparência sobre o status de planejamento (sem código implementado) estabelece expectativas corretas para quem avalia o portfólio.

### Negativas

- A ADR-00 precisa ser lida antes das demais para que o racional de custo e aprendizado faça sentido. Não há como estruturar as ADRs de forma que sejam completamente independentes — esse acoplamento é intrínseco ao projeto.
- Documentar que o projeto foi desenvolvido com Claude Code pode gerar questionamentos sobre a autoria das decisões. Cabe ao autor demonstrar, nas entrevistas técnicas, que o raciocínio arquitetural é compreendido e pode ser defendido sem a ferramenta.

---

## Dependências

**Esta ADR não depende de nenhuma outra.**

As seguintes ADRs dependem diretamente desta:

| ADR | Decisão | Dependência da ADR-00 |
|-----|---------|----------------------|
| ADR-01 | Orquestrador (Apache Airflow 2.8) | Objetivo de aprendizado e público-alvo justificam Airflow sobre Prefect/Dagster |
| ADR-02 | Formato de armazenamento (Delta Lake) | Constraint de custo elimina BigQuery; objetivo de portfólio justifica `open table format` |
| ADR-03 | Ambiente de execução Spark (Dataproc) | Constraint de $300 elimina cluster permanente; objetivo de aprendizado elimina `local[*]` |
| ADR-04 | Ciclo de vida do cluster (efêmero) | Constraint de $300 torna cluster permanente inviável |
| ADR-05 | Qualidade de dados (assertions PySpark) | Foco em PySpark como objetivo de aprendizado é o critério de coerência da escolha |
| ADR-06 | Deployment do Airflow (VM + Docker Compose) | Constraint de $300 elimina Cloud Composer (~$300/mês) |
| ADR-07 | Arquitetura Medalhão | Constraints globais justificam arquitetura batch-only sem streaming |
| ADR-08 | Provisionamento IaC (Terraform) | Escopo do projeto e objetivo de portfólio para vagas Pleno |

---

## Checklist de Pontos Pendentes de Verificação

Esta seção consolida todos os pontos marcados com `[VERIFICAR]` nas ADRs do projeto. O objetivo é evitar que esses pontos se percam durante a implementação. Cada item deve ser revisado e confirmado antes de considerar a decisão correspondente como `Aceita`.

| # | ADR | Ponto a verificar |
|---|-----|-------------------|
| 1 | ADR-02 | Confirmar a combinação exata de versões antes de criar o ambiente: Dataproc 2.2, Spark 3.5.x (pré-instalado na imagem 2.2), `delta-spark` 3.2.0 e Scala 2.12. Versões incompatíveis geram erros de classpath em runtime — a validação precisa ocorrer contra a imagem Dataproc efetivamente disponível no GCP no momento de provisionamento do cluster. |
| 2 | ADR-02 | Consequência direta do item 1: versões incompatíveis entre `delta-spark` e o Spark da imagem Dataproc falham em runtime, não em compilação. O ponto de verificação das versões na seção Negativas da ADR-02 reforça que a combinação documentada é referência, não garantia — e deve ser validada antes da configuração do ambiente. |
| 3 | ADR-03 | Confirmar os preços atuais do tipo de máquina e2-standard-2 para a região de deployment (referência: `us-central1`) em [https://cloud.google.com/compute/vm-instance-pricing](https://cloud.google.com/compute/vm-instance-pricing). A estimativa de ~$0.10/hora de cluster ativo foi usada no planejamento de custo; variações de preço afetam as projeções de consumo de créditos GCP documentadas na ADR-03 e na ADR-04. |
| 4 | ADR-04 | O TTL configurado no `lifecycle_config.auto_delete_ttl` (estimativa inicial: 60–90 minutos, correspondente a 2× o tempo esperado de execução completa do pipeline) precisa ser medido e ajustado após as primeiras execuções de validação. Se o TTL for subdimensionado, o Dataproc destrói o cluster durante uma execução legítima. Se for superdimensionado, reduz a eficácia da proteção contra cluster órfão. |
| 5 | ADR-04 | Confirmar os preços atuais do e2-standard-2 para a região de deployment em [https://cloud.google.com/compute/vm-instance-pricing](https://cloud.google.com/compute/vm-instance-pricing). As estimativas de custo por cenário documentadas na tabela da ADR-04 (execução normal, falha com Camada 1, falha com Camada 2, cluster órfão sem proteção) usam ~$0.10/hora como referência e precisam ser recalibradas se o preço real diferir. |
| 6 | ADR-05 | A lista de campos obrigatórios para promoção Bronze → Silver (`sg_empresa`, `cd_origem`, `cd_destino`, `ano_referencia`, `mes_referencia`) e os domínios de validação dos campos numéricos precisam ser confirmados contra o schema real do CSV da ANAC durante a fase de implementação. O dataset da ANAC tem histórico documentado de variações de schema — os campos listados na ADR-05 são os mais prováveis de permanecerem estáveis, mas não estão validados contra os arquivos reais. |
| 7 | ADR-05 | O limiar de variação tolerado na assertion de negócio Silver → Gold (atualmente fixado em 30% de variação nos totais agregados entre períodos consecutivos) precisa ser calibrado após as primeiras execuções reais com dados históricos. O valor de 30% é uma estimativa conservadora de planejamento — pode gerar falsos positivos ou ser insuficiente dependendo do comportamento histórico real do dataset. |
| 8 | ADR-06 | Confirmar o preço atualizado da VM e2-medium para a região de deployment em [https://cloud.google.com/compute/vm-instance-pricing](https://cloud.google.com/compute/vm-instance-pricing). A estimativa de ~$25–30/mês foi usada no planejamento de viabilidade dentro do free trial de $300. Essa estimativa determina por quantos meses o orçamento suporta a VM do Airflow ativa. |
| 9 | ADR-07 | O limiar de variação histórica de contagem de registros que bloqueia a promoção Silver → Gold (atualmente 30%) precisa ser calibrado após os primeiros ciclos de execução real. O valor foi definido na fase de planejamento sem dados históricos reais do dataset ANAC — pode precisar de ajuste tanto para cima (se o dataset tem variações naturais maiores) quanto para baixo (se o dado é mais estável do que o esperado). Este ponto é compartilhado com o item 7 desta tabela (ADR-05), que aplica o mesmo critério nas assertions de qualidade. |
| 10 | ADR-08 | ✓ Resolvido: bootstrap do Docker declarado como `metadata_startup_script` no recurso `google_compute_instance`. O `terraform apply` produz uma VM com Docker CE + Docker Compose plugin instalados e o serviço habilitado. |
| 11 | ADR-08 | ✓ Resolvido: lifecycle rules em Silver e Gold para prefixo `_spark_staging/` com expiração de 7 dias. Bronze sem lifecycle rules (fonte da verdade imutável, ADR-07). |
| 12 | ADR-08 | ✓ Resolvido: `sa-airflow` — `roles/dataproc.editor`, `roles/storage.objectAdmin` (3 buckets), `roles/secretmanager.secretAccessor`. `sa-dataproc` — `roles/dataproc.worker`, `roles/storage.objectAdmin` (3 buckets). |
| 13 | ADR-08 | ✓ Resolvido: VPC default do GCP com firewall rules explícitas. VPC dedicada rejeitada por adicionar complexidade de configuração de rede sem benefício funcional para o escopo do projeto. |
| 14 | ADR-08 | ✓ Resolvido: remote state em bucket GCS, com bootstrap via Opção A — criar o bucket de state manualmente com `gcloud` uma única vez antes do primeiro `terraform apply`, documentado como pré-requisito obrigatório no README. Terraform-dentro-de-Terraform (Opção B) rejeitado por complexidade desnecessária. |
| 15 | ADR-08 | ✓ Resolvido: chave JSON de service account armazenada como GitHub Secret (`GOOGLE_CREDENTIALS`). Workload Identity Federation rejeitado por adicionar complexidade de configuração (pool de identidades, provider OIDC, binding) sem valor proporcional para um projeto de portfólio. |
| 16 | ADR-08 | ✓ Resolvido: escopo intermediário — `terraform fmt --check` + `terraform validate` + `terraform plan` no PR com output publicado como comentário. `terraform apply` automatizado no merge rejeitado por risco com billing real ativo. Escopo mínimo rejeitado por não demonstrar integração real com GCP em CI. |
| 17 | ADR-08 | ✓ Resolvido: `*.tfstate`, `*.tfstate.backup` e `*.tfstate.lock.info` estão no `.gitignore` do repositório. |
