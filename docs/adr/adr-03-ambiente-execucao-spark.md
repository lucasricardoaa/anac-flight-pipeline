# ADR-03: Ambiente de Execução do PySpark — Google Cloud Dataproc

## Status

Proposta

> _Esta decisão foi tomada durante a fase de planejamento — nenhuma fase do projeto foi implementada. O status será revisado para `Aceita` após implementação e validação em ambiente real._

---

## Contexto

### O problema de onde executar o PySpark

O pipeline de dados da ANAC processa CSVs mensais com PySpark em arquitetura Medalhão (Bronze/Silver/Gold) sobre Delta Lake. O Delta Lake exige que o Spark seja capaz de ler e escrever em `gs://` — o que requer o `gcs-connector-hadoop3` configurado corretamente no classpath do Spark. O ambiente de execução do PySpark não é um detalhe operacional: ele determina como o Spark acessa o storage, como os jobs são submetidos pelo Airflow e, mais importante para este projeto, o que de fato está sendo demonstrado no portfólio.

### A distinção que determina esta decisão

A API do PySpark é idêntica em qualquer ambiente: `spark.read.csv(...)`, `df.write.format("delta").save(...)`, `df.groupBy(...).agg(...)`. Código PySpark escrito para rodar em `local[*]` roda em um cluster Dataproc com nenhuma ou mínima modificação. A API não diferencia.

O que diferencia é o que acontece por baixo: em modo `local[*]`, o PySpark executa em múltiplas threads dentro de um único processo JVM, na mesma VM onde o código roda. Não há workers separados, não há YARN como resource manager, não há shuffle entre nós, não há executor JVM isolado. É a API do Spark sem o Spark distribuído.

Para um portfólio que inclui Spark como competência central, essa distinção é direta: demonstrar apenas a API do PySpark sem o runtime distribuído é honesto sobre o que foi aprendido, mas não é o que o mercado de vagas Pleno espera quando vê "PySpark no GCP" em um projeto de portfólio.

### Constraints que delimitam o espaço de soluções

Dois constraints documentados na ADR-00 delimitam as opções:

1. **Constraint financeiro**: $300 em créditos GCP. Um cluster Dataproc e2-standard-2 com 1 master + 2 workers consome aproximadamente $0.10/hora. Rodando continuamente, isso resulta em ~$200/mês — somente para o cluster parado, sem executar nenhum job. Esse valor sozinho elimina cluster permanente como opção dentro do orçamento do projeto.

2. **Objetivo de portfólio**: demonstrar Spark distribuído real, não apenas a API. Um cluster gerenciado no GCP com YARN, workers separados e shuffle distribuído entre nós é o que aparece em JDs de vagas enterprise no Brasil.

---

## Decisão

**O PySpark é executado em cluster Google Cloud Dataproc provisionado dinamicamente no GCP.**

A configuração de referência do cluster é: 1 master e2-standard-2 (2 vCPUs, 8 GB RAM) + 2 workers e2-standard-2. A série `e2` é suportada em clusters Dataproc a partir da imagem 2.0 e está disponível em todas as regiões GCP padrão, incluindo `us-central1`. A imagem 2.2, adotada neste projeto conforme ADR-02, é compatível com o tipo `e2-standard-2` sem restrições. O cluster é criado imediatamente antes da execução dos jobs Spark e destruído imediatamente após — essa estratégia de ciclo de vida efêmero é o que torna o Dataproc viável dentro do constraint de $300 e está documentada na ADR-04.

O ciclo de vida do cluster é orquestrado pelo Airflow via operadores nativos: `DataprocCreateClusterOperator`, `DataprocSubmitJobOperator` e `DataprocDeleteClusterOperator`. A integração com o orquestrador definido na ADR-01 é direta e sem necessidade de operadores customizados.

A imagem do cluster Dataproc utilizada é compatível com `delta-spark` na versão adotada no projeto. A combinação específica de versões está documentada na ADR-02 e marcada como `[VERIFICAR]` até ser validada contra a imagem efetivamente disponível no GCP no momento de criação do cluster.

---

## Alternativas consideradas

### PySpark em `local[*]` na VM do Airflow

**O que é**: execução do PySpark diretamente na VM onde o Airflow está rodando (e2-medium com Docker Compose, conforme ADR-06), usando o modo `local[*]`. O Spark usa múltiplas threads do processo JVM para simular paralelismo, sem workers separados.

**Vantagens técnicas**: zero custo adicional de infraestrutura — não requer provisionamento de cluster no GCP. Zero latência de cold start — a execução começa imediatamente, sem aguardar os 3–5 minutos de provisionamento do Dataproc. A API do PySpark é idêntica, então o código desenvolvido localmente funciona sem modificação.

**Por que foi rejeitado**: não demonstra Spark distribuído. Em `local[*]`, o PySpark executa em um único processo JVM com múltiplas threads — sem YARN como resource manager, sem workers separados, sem shuffle distribuído entre nós, sem múltiplos executores reais. O que é executado é a API do Spark, não o runtime distribuído do Spark.

Para um portfólio com objetivo declarado de demonstrar PySpark em ambiente enterprise, essa opção seria desonesta com o avaliador. Um engenheiro experiente que revisar o projeto e perceber que "PySpark no GCP" se traduz em `local[*]` em uma VM e2-medium vai interpretar isso como limitação técnica do autor — não como decisão de design. A rejeição desta alternativa é a razão central pela qual o Dataproc foi escolhido.

---

### Cluster Dataproc permanente (sem destruição entre execuções)

**O que é**: cluster Dataproc provisionado uma única vez e mantido rodando continuamente, sem ciclo de vida efêmero. Jobs Spark são submetidos ao cluster existente sem overhead de provisionamento.

**Vantagens técnicas**: elimina o cold start de 3–5 minutos por execução. Jobs Spark são submetidos imediatamente a um cluster já disponível. YARN já inicializado, workers já registrados — a latência de execução é determinada apenas pelo job em si.

**Por que foi rejeitado**: custo proibitivo dentro do constraint de $300 documentado na ADR-00.

A configuração de referência (1 master e2-standard-2 + 2 workers e2-standard-2) custa aproximadamente $0.10/hora de cluster ativo. Rodando continuamente por 30 dias, o custo do cluster parado — sem executar nenhum job — é de ~$72/mês. Para um cluster ligeiramente maior, o custo supera $200/mês com facilidade.

Com o free trial de $300 em créditos GCP, um cluster permanente consumiria o orçamento total do projeto em menos de dois meses, sem considerar os custos de VM do Airflow (ADR-06), storage no GCS, tráfego de rede ou outros serviços GCP. A estratégia de cluster efêmero com destruição após cada execução, documentada na ADR-04, é o que torna o custo do Dataproc compatível com o orçamento disponível.

---

### Dataproc Serverless

**O que é**: modalidade do Dataproc sem gestão de cluster. O job PySpark é submetido diretamente à API do Dataproc Serverless, que aloca recursos automaticamente, executa o job e libera os recursos ao final. Não há cluster para provisionar ou destruir — o recurso gerenciado é o batch job, não o cluster.

**Vantagens técnicas**: elimina o overhead de gestão de cluster — sem `DataprocCreateClusterOperator`, sem `DataprocDeleteClusterOperator`, sem risco de cluster órfão. O custo é proporcional à computação efetivamente utilizada, sem cobrança por tempo de cluster parado.

**Por que foi rejeitado**: três razões, em ordem de peso.

Primeiro, **custo menos previsível durante a fase de desenvolvimento**. O Dataproc Serverless cobra por DCU-hora (Data Compute Unit), com custo que varia conforme os recursos alocados automaticamente pelo serviço. Durante o desenvolvimento — quando o número de execuções de teste é alto e os jobs frequentemente falham parcialmente — a variabilidade de custo por execução é maior do que em um cluster com configuração fixa. Com o Dataproc gerenciado e a estratégia efêmera da ADR-04, o custo por execução é previsível: ~$0.10/hora × ~20 minutos = $0.03–0.05 por execução completa.

Segundo, **menor valor didático como demonstração**. O Dataproc Serverless abstrai o conceito de cluster Spark — YARN, workers, resource manager — que é parte do que este projeto pretende demonstrar. Para o objetivo de portfólio, demonstrar que se sabe operar um cluster Dataproc (com suas configurações de imagem, propriedades de cluster, gerenciamento de ciclo de vida) tem mais valor do que demonstrar a submissão de batch jobs para uma API que abstrai esses conceitos.

Terceiro, **menor presença em materiais de estudo e JDs**. O Dataproc gerenciado com clusters YARN é o modelo de referência na maior parte dos tutoriais, cursos e vagas de Engenheiro de Dados Pleno no Brasil. Dataproc Serverless é mais recente e ainda menos representado nesse ecossistema. O objetivo de aprendizado deste projeto se beneficia mais de operar o modelo de cluster tradicional.

---

### Spark em container Docker standalone na VM

**O que é**: cluster Spark multi-container usando Docker Compose na própria VM do Airflow (ou em uma VM dedicada), com um container de master e dois de worker. O Spark roda em modo standalone (sem YARN), com o master coordenando os workers via protocolo Spark nativo.

**Vantagens técnicas**: demonstra Spark distribuído real — workers separados, shuffle entre containers, múltiplos executores. Custo zero de infraestrutura de Spark (sem Dataproc, sem cobranças adicionais). Independência de GCP para o runtime Spark — o pipeline pode rodar em qualquer máquina com Docker.

**Por que foi rejeitado**: dois motivos.

Primeiro, **complexidade de setup não trivial**. Um cluster Spark standalone com Docker Compose envolve configuração de rede entre containers (master e workers precisam se comunicar por nome de host, não por IP), configuração de volumes para logs e dados, alinhamento de versões de imagem Spark com `delta-spark` e com o Java instalado no container. A integração com o Airflow (que precisa submeter jobs ao master Spark) requer configuração adicional do `SparkSubmitOperator` ou endpoint REST do master. Esse overhead de configuração é real e não trivial para um primeiro projeto com Spark.

Segundo, **não demonstra integração com infraestrutura cloud real**. O objetivo central da escolha do Dataproc é demonstrar Spark operando de forma integrada com GCP — IAM, GCS, operadores Airflow para Dataproc. Um cluster Docker standalone na VM demonstra Spark distribuído, mas sem nenhuma dessas integrações. Para o portfólio, o valor de demonstrar "Spark distribuído integrado ao GCP com ciclo de vida gerenciado pelo Airflow" é superior ao de "Spark distribuído em Docker Compose".

---

## Consequências

### O que o Dataproc habilita neste projeto

**Cluster gerenciado com Spark pré-instalado**: a imagem Dataproc já inclui Spark, Hadoop, YARN e as configurações necessárias para execução distribuída. Não há necessidade de provisionar JVM, instalar dependências do Spark ou configurar o YARN manualmente. O cluster está pronto para receber jobs Spark imediatamente após o provisionamento.

**Integração nativa com GCS via IAM do GCP**: o Dataproc opera com a identidade de serviço (Service Account) configurada no cluster. O acesso ao bucket GCS onde estão os dados da ANAC e as tabelas Delta Lake é controlado por IAM do GCP — sem gerenciamento de credenciais adicionais no código ou no SparkSession. O `gcs-connector-hadoop3` está disponível por padrão na imagem do cluster, sem necessidade de adicioná-lo manualmente ao job.

**Operadores nativos no Airflow**: o provedor `apache-airflow-providers-google` inclui `DataprocCreateClusterOperator`, `DataprocSubmitJobOperator` e `DataprocDeleteClusterOperator` como operadores de primeira classe. A integração com o orquestrador definido na ADR-01 é direta: o DAG cria o cluster, submete os jobs por camada (Bronze, Silver, Gold), destrói o cluster. Nenhum operador customizado é necessário.

**Autenticidade de demonstração**: com YARN como resource manager, shuffle distribuído entre master e workers e múltiplos executores reais (um por worker), a execução no Dataproc é o que aparece em ambientes enterprise. Um avaliador externo vê Spark distribuído real operando sobre dados reais no GCP — não a API do Spark simulando paralelismo em threads locais.

**Delta Lake sobre GCS**: a presença padrão do `gcs-connector-hadoop3` na imagem Dataproc resolve a principal fricção de integração entre Delta Lake e GCS documentada na ADR-02. O conector está no classpath do Spark sem configuração adicional, o que permite que o `_delta_log` seja lido e escrito em `gs://` sem erros de `FileSystem` que seriam comuns em ambientes fora do Dataproc.

### Estimativa de custo por execução

Configuração de referência: 1 master e2-standard-2 (2 vCPUs, 8 GB RAM) + 2 workers e2-standard-2. Preço estimado do cluster ativo: ~$0.10/hora.

`[VERIFICAR]` — os preços dos tipos de máquina e2-standard-2 no GCP variam por região e podem ter sido atualizados. A estimativa abaixo usa valores de referência para a região `us-central1`. Confirmar em [https://cloud.google.com/compute/vm-instance-pricing](https://cloud.google.com/compute/vm-instance-pricing) antes de finalizar o planejamento de custo.

Uma execução completa do pipeline — provisionamento do cluster (3–5 minutos), jobs Spark de ingestão e transformação para Bronze, Silver e Gold (5–10 minutos), destruição do cluster (2–3 minutos) — leva aproximadamente 15–20 minutos de cluster ativo. Custo por execução: **$0.03–0.05**.

Projeção de consumo ao longo do projeto:

| Cenário | Execuções | Custo estimado (Dataproc) |
|---|---|---|
| Desenvolvimento e testes | 100 execuções | ~$3–5 |
| Operação recorrente (12 meses mensais) | 12 execuções | ~$0.40–0.60 |
| Total estimado | 112 execuções | ~$4–6 |

O custo total de Dataproc ao longo de todo o projeto de desenvolvimento permanece em torno de $4–6 — menos de 2% do orçamento de $300 em créditos GCP. Essa proporção valida a decisão de usar Dataproc gerenciado com cluster efêmero: o custo é compatível com o constraint e a autenticidade de demonstração justifica o overhead em relação ao `local[*]`.

### Consequências negativas

**Cold start de 3–5 minutos por execução**: cada execução do pipeline aguarda o provisionamento completo do cluster Dataproc antes que o primeiro job Spark possa ser submetido. Em produção, essa latência seria inaceitável para a maioria dos casos de uso. No contexto deste projeto — pipeline batch mensal, execução agendada — é um trade-off aceito e documentado na ADR-00 como consequência deliberada da estratégia de cluster efêmero.

**Risco de cluster órfão**: se o Airflow falhar após criar o cluster e antes de executar a task de destruição, o cluster permanece rodando acumulando custo. A mitigação desse risco — `trigger_rule='all_done'` na task de destruição, além de mecanismo de proteção complementar — é documentada na ADR-04.

**Dependência de GCP durante o desenvolvimento**: sem acesso ao GCP, o desenvolvimento de jobs PySpark requer um ambiente alternativo. O modo `local[*]` pode ser usado para desenvolvimento e teste unitário de transformações, com execução final em Dataproc para validação integrada. Essa dualidade é intencional: `local[*]` para iteração rápida de lógica de transformação, Dataproc para validação do pipeline completo.

**Compatibilidade de versões como ponto de atenção**: a versão do Spark disponível no Dataproc é determinada pela imagem do cluster. A imagem precisa ser compatível com a versão de `delta-spark` adotada no projeto — versões incompatíveis geram erros de classpath em runtime, não em tempo de compilação. A combinação validada está documentada na ADR-02 como `[VERIFICAR]` e precisa ser confirmada antes da criação do cluster.

---

## Dependências

### Esta ADR depende de

| ADR | Dependência |
|---|---|
| ADR-00 | O constraint de $300 em créditos GCP elimina cluster Dataproc permanente como opção. O objetivo de portfólio para vagas Pleno elimina `local[*]` como opção. Sem o contexto formalizado na ADR-00, a rejeição de ambas as alternativas seria incompreensível. |
| ADR-02 | O Delta Lake requer o `gcs-connector-hadoop3` para ler e escrever em `gs://`. A presença desse conector por padrão na imagem Dataproc é uma das razões pelas quais o Dataproc resolve a fricção de integração documentada na ADR-02. A combinação de versões Dataproc + Spark + `delta-spark` definida nesta ADR precisa ser consistente com a especificada na ADR-02. |

### Esta ADR é dependência de

| ADR | Dependência |
|---|---|
| ADR-04 | O ciclo de vida do cluster Dataproc (criação, uso e destruição em cada execução do pipeline) pressupõe a escolha do Dataproc gerenciado documentada nesta ADR. A estratégia de cluster efêmero e a proteção contra cluster órfão são consequências diretas dessa escolha. |
| ADR-08 | O Terraform provisiona o cluster Dataproc com a configuração correta — imagem, tipo de máquina, propriedades de cluster para o `gcs-connector-hadoop3`, Service Account com permissões IAM para o bucket GCS. As especificações de configuração que o Terraform precisa implementar decorrem das decisões documentadas nesta ADR. |

---

## Referências

- ADR-00: Contexto Global e Constraints do Projeto
- ADR-01: Orquestrador de Pipelines (Apache Airflow 2.8)
- ADR-02: Formato de Armazenamento (Delta Lake sobre GCS)
- ADR-04: Ciclo de Vida do Cluster Dataproc (a ser criada)
- ADR-08: Provisionamento de Infraestrutura com Terraform (a ser criada)
- [Google Cloud Dataproc — Versioning and supported open source components](https://cloud.google.com/dataproc/docs/concepts/versioning/overview)
- [Google Cloud Dataproc — Cloud Storage connector](https://cloud.google.com/dataproc/docs/concepts/connectors/cloud-storage)
- [Apache Airflow — Google Cloud Dataproc Operators](https://airflow.apache.org/docs/apache-airflow-providers-google/stable/operators/cloud/dataproc.html)
- [Google Cloud — VM instance pricing (e2-standard-2)](https://cloud.google.com/compute/vm-instance-pricing)
- [Delta Lake — Releases and Spark compatibility](https://docs.delta.io/latest/releases.html)
