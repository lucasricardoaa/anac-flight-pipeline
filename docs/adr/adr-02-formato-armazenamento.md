# ADR-02: Formato de Armazenamento e Open Table Format — Delta Lake sobre GCS

## Status

Proposta

> _Esta decisão foi tomada durante a fase de planejamento — nenhuma fase do projeto foi implementada. O status será revisado para `Aceita` após implementação e validação em ambiente real._

---

## Contexto

O projeto armazena e processa dados de transporte aéreo doméstico brasileiro publicados pela ANAC em formato CSV mensal. A arquitetura Medalhão (Bronze/Silver/Gold) requer um protocolo de tabela que ofereça: garantias transacionais na promoção entre camadas, rastreabilidade de versões para reprocessamento e controle explícito de schema evolution.

Os dados da ANAC têm características relevantes para esta decisão:

- **Volume**: dataset CSV mensal de tamanho moderado. Não é Big Data no sentido técnico — cabe em um único worker Dataproc sem pressão de memória. O critério de escolha do formato não é performance em escala massiva, mas adequação à arquitetura Medalhão e demonstração de conhecimento de `open table format` para o mercado de vagas Pleno.
- **Schema instável**: o CSV da ANAC sofreu alterações de schema em versões históricas — adição de colunas e renomeação de campos documentados em diferentes períodos de publicação. Um formato sem mecanismo de `schema enforcement` ingressa dados malformados silenciosamente.
- **Reprocessamento histórico**: o pipeline precisa ser capaz de reprocessar camadas intermediárias (Silver, Gold) sem re-ingerir da fonte ANAC. Os CSVs históricos estão disponíveis, mas re-ingestão é um processo custoso e desnecessário se o dado já está persistido com versionamento.

O constraint financeiro documentado na ADR-00 ($300 em créditos GCP) elimina qualquer alternativa de storage gerenciado pago como BigQuery. O objetivo de portfólio documentado na mesma ADR exige demonstração explícita de `open table format`, o que elimina Parquet puro como opção.

O ambiente de execução é Dataproc (GCP), com PySpark. O storage é Google Cloud Storage. Essas são as variáveis de contexto que diferenciam esta decisão de uma decisão genérica sobre `open table format`.

---

## Decisão

**Delta Lake via `delta-spark` é o `open table format` adotado para todas as camadas da arquitetura Medalhão (Bronze, Silver e Gold), com tabelas armazenadas no Google Cloud Storage e processamento via Spark no Dataproc.**

As features do Delta Lake são utilizadas de forma específica em cada camada:

- **ACID transactions**: aplicadas na promoção entre camadas. A escrita em Silver após validação da Bronze é atômica — um leitor da Silver nunca vê um estado intermediário de promoção. O mesmo vale para a promoção Silver → Gold. Sem essa garantia, uma falha parcial durante a promoção gera um estado inconsistente que exige intervenção manual para recuperação.

- **Time travel**: utilizado para reprocessamento seletivo de camadas intermediárias. Se um bug é introduzido na transformação que produz a Silver, o pipeline pode reprocessar a partir da versão correta da Bronze sem re-ingerir da fonte ANAC. Isso é especialmente relevante para o dataset histórico da ANAC: os CSVs de anos anteriores estão disponíveis, mas re-ingestão é desnecessária quando o dado já está versionado na Bronze.

- **Schema enforcement**: aplicado na camada Bronze como ponto de entrada da estratégia de schema evolution. Qualquer ingestão que viole o schema registrado falha antes de persistir dados. A postura adotada é descrita na seção de Consequências.

### Combinação de versões validada

`[VERIFICAR]` — a combinação abaixo deve ser confirmada contra a imagem Dataproc efetivamente utilizada no projeto antes de finalizar a configuração do ambiente.

| Componente | Versão |
|---|---|
| Dataproc | 2.2 |
| Spark (pré-instalado na imagem Dataproc 2.2) | 3.5.x |
| `delta-spark` | 3.2.0 (compatível com Spark 3.5.x) |
| Scala (artifact coordinate) | 2.12 |

Configuração obrigatória no SparkSession:

```python
spark = (
    SparkSession.builder
    .config("spark.jars.packages", "io.delta:delta-spark_2.12:3.2.0")
    .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
    .config(
        "spark.sql.catalog.spark_catalog",
        "org.apache.spark.sql.delta.catalog.DeltaCatalog",
    )
    .getOrCreate()
)
```

No Dataproc, o `gcs-connector-hadoop3` já está disponível na imagem padrão — não é necessário adicionar o jar manualmente ao SparkSession. A configuração do conector via propriedades Hadoop (`fs.gs.impl`) deve estar presente nas propriedades do cluster Dataproc, conforme especificado na ADR-03.

---

## Alternativas consideradas

### Parquet puro

Rejeitado.

Parquet é um formato colunar eficiente para leitura analítica e seria tecnicamente suficiente para ler e escrever os dados da ANAC. O problema não é o formato — é a ausência de protocolo de tabela sobre ele.

Sem um `open table format` sobre o Parquet, o projeto perde:

- **ACID transactions**: não há garantia de atomicidade na promoção entre camadas Medalhão. Uma falha no meio de uma escrita em Silver gera arquivos Parquet parcialmente escritos que o Spark lê sem reclamação, silenciosamente corrompendo os resultados downstream.
- **Time travel**: sem versionamento, reprocessar a Silver a partir de uma versão anterior da Bronze requer re-ingestão da fonte ANAC ou manutenção manual de snapshots — ambos processos frágeis.
- **Schema enforcement nativo**: qualquer dado malformado entra na Bronze sem resistência. Em um dataset com histórico de mudanças de schema como o da ANAC, isso é um risco operacional concreto.

Rejeitar Parquet puro também é coerente com o objetivo de portfólio: demonstrar conhecimento de `open table format` é um diferencial explícito em JDs de vagas Engenheiro de Dados Pleno no Brasil. Usar Parquet puro seria tecnicamente defensável para este volume de dados, mas irrelevante como demonstração de habilidade.

---

### Apache Iceberg

Rejeitado por razão específica de contexto. Não por inferioridade técnica.

Iceberg é a alternativa mais séria que foi considerada. Seus atributos técnicos merecem documentação honesta:

**Atributos técnicos do Iceberg que são genuinamente superiores ao Delta Lake neste contexto:**

- **Especificação aberta (Apache Software Foundation)**: Iceberg é uma especificação, não uma implementação de vendor. Isso significa que a evolução da especificação é governada por um processo de comunidade, sem dependência de uma empresa específica. Delta Lake é mantido pela Databricks, que tem incentivos comerciais que podem divergir dos interesses da comunidade.
- **Suporte multi-engine sem adaptadores**: Spark, Flink, Trino, Athena e Snowflake leem e escrevem tabelas Iceberg nativamente, sem connectors adicionais. Em um projeto com múltiplos engines de query, Iceberg elimina fricções de integração que o Delta Lake pode introduzir.
- **Hidden partitioning e partition evolution**: Iceberg permite mudar a estratégia de particionamento sem reescrever os dados existentes. No Delta Lake, mudar o esquema de particionamento requer reescrever a tabela inteira. Para um dataset que cresce mensalmente, a capacidade de evoluir o particionamento sem reescrever é relevante.
- **Row-level deletes eficientes via delete files**: Iceberg suporta deleção lógica de linhas sem reescrever o arquivo Parquet subjacente. O Delta Lake requer reescrever o arquivo em operações de `UPDATE` e `DELETE` em muitos casos.
- **Compatibilidade com GCS sem fricções adicionais**: Iceberg não tem dependência documentada de um conector específico para GCS além do SDK padrão. O Delta Lake, como descrito na seção de fricções conhecidas, requer atenção ao `gcs-connector-hadoop3`.

**Por que Iceberg foi rejeitado neste projeto:**

A rejeição é inteiramente contextual. Este projeto usa Spark batch em Dataproc, sem Flink, sem Trino, sem Athena, sem nenhum segundo engine de query. O atributo mais forte do Iceberg — interoperabilidade multi-engine — não é exercitado.

O critério que determinou a escolha foi a maturidade do ecossistema de tutoriais, documentação e troubleshooting para a combinação específica `delta-spark` + Spark 3.5 + Dataproc. O volume de material de referência disponível para esse stack — Stack Overflow, documentação da Databricks, posts de comunidade — é maior e mais detalhado do que o material equivalente para Iceberg + Spark + Dataproc. Para um projeto com objetivo declarado de aprendizado, menor fricção de debug tem peso real.

Iceberg seria a escolha correta nos seguintes cenários:

- Projeto com múltiplos engines de query (ex: ingestão via Spark, consultas via Trino ou Athena)
- Requisito explícito de portabilidade entre clouds (GCP hoje, AWS amanhã)
- Requisito de partition evolution sem reescrita de dados históricos
- Contexto em que independência de vendor é um critério formal de arquitetura

Nenhum desses cenários se aplica a este projeto. A rejeição não invalida Iceberg como escolha em outros contextos.

---

### BigQuery como camada de storage

Rejeitado.

BigQuery é um serviço de data warehouse gerenciado com modelo de cobrança por consulta ($5/TB processado em on-demand) ou por slot reservation (custo fixo mensal). Adotá-lo como camada de storage introduziria:

- **Dependência de serviço gerenciado pago**: diretamente incompatível com o constraint de $300 em créditos GCP documentado na ADR-00. O custo de consultas sobre dados históricos da ANAC durante o desenvolvimento e testes consumiria uma fração não negligenciável do orçamento disponível.
- **Desvio do objetivo arquitetural**: o objetivo deste projeto é demonstrar lakehouse com `open table format` sobre object storage — esse é o padrão arquitetural presente em JDs de vagas enterprise no Brasil. BigQuery como storage substitui esse padrão por um serviço gerenciado que abstrai as decisões que o projeto pretende demonstrar.
- **Acoplamento a GCP**: BigQuery é um serviço exclusivo do GCP. Um recrutador avaliando o portfólio de um candidato que usou BigQuery como storage vê conhecimento de um serviço GCP-específico, não conhecimento de um padrão de arquitetura transferível.

BigQuery como camada de consumo analítico (destino final de tabelas Gold para dashboards) é uma decisão diferente e não é o escopo desta ADR.

---

### Apache Hudi

Considerado brevemente, rejeitado na avaliação inicial.

Hudi tem caso de uso primário em pipelines com requisito de upsert incremental em alta frequência — cenário de CDC (Change Data Capture) onde registros chegam continuamente e precisam ser mesclados em uma tabela de destino. O dataset da ANAC é batch mensal sem requisito de upsert incremental de alta frequência. O caso de uso principal do Hudi não se aplica.

Adicionalmente, a curva de aprendizado do Hudi (configuração de `table type`, `index type`, gerenciamento do `timeline`) é mais íngreme do que a do Delta Lake para o mesmo resultado funcional neste contexto. Para um projeto com objetivo de aprendizado em PySpark e Airflow — não em Hudi especificamente — essa fricção adicional não produz retorno de aprendizado proporcional.

---

## Consequências

### Positivas

- **ACID transactions** garantem que o estado de qualquer camada Medalhão é consistente em qualquer ponto de observação. Falhas no pipeline não geram estados intermediários visíveis para leitores downstream.
- **Time travel** elimina a necessidade de re-ingestão da fonte ANAC para reprocessamento. O pipeline pode retornar a qualquer versão da Bronze e reprocessar as camadas superiores sem contato com a fonte original.
- **Schema enforcement** na Bronze garante que dados malformados são rejeitados antes de contaminar as camadas Silver e Gold. O problema é detectado na fronteira de entrada, não descoberto durante análise downstream.
- A escolha é coerente com o objetivo de portfólio: demonstra conhecimento de `open table format`, ACID em lakehouse e `schema evolution` — competências presentes em JDs de vagas Engenheiro de Dados Pleno no Brasil.

### Fricções conhecidas — Delta Lake sobre GCS

Delta Lake foi projetado originalmente para HDFS e, posteriormente, otimizado para Amazon S3. O suporte a GCS é real e documentado pela comunidade, mas com fricções conhecidas que precisam ser tratadas explicitamente:

**Conector obrigatório (`gcs-connector-hadoop3`)**: o Delta Lake precisa que o Hadoop FileSystem para GCS (`gs://`) esteja configurado corretamente para ler e escrever o `_delta_log`. No Dataproc, esse conector está disponível na imagem padrão e não requer instalação manual. Em ambientes fora do Dataproc (ex: testes locais contra um bucket GCS), a configuração do conector precisa ser feita explicitamente no SparkSession. Esse requisito não existe no Iceberg com a mesma intensidade.

**Performance de listagem de objetos**: operações Delta Lake que exigem listagem de muitos objetos no GCS — `VACUUM` (limpeza de arquivos antigos), `OPTIMIZE` (compactação de arquivos pequenos) — podem ser mais lentas do que as equivalentes no S3. A API de listagem do GCS tem características diferentes da API do S3, e o Delta Lake foi otimizado para o segundo. Para o volume do dataset da ANAC (CSV mensal, não Big Data), esse trade-off é aceitável. Em datasets com centenas de milhões de arquivos, seria um fator de decisão.

**Operações concorrentes**: o mecanismo de controle de concorrência do Delta Lake (`_delta_log` com commits sequenciais) pode apresentar conflitos em cenários de alta concorrência com latência de rede elevada. Este pipeline é single-writer por design — um job Dataproc escreve em cada tabela por vez, sem concorrência. O risco não se aplica.

Esses três pontos são riscos aceitos e mitigáveis dentro do contexto deste projeto, não bloqueantes.

### Estratégia de schema evolution — postura explícita

O dataset da ANAC tem histórico documentado de mudanças de schema entre versões mensais. Definir o comportamento de `schema evolution` como padrão não documentado é um risco operacional: o Delta Lake tem comportamentos diferentes dependendo da configuração, e o comportamento default (falha em qualquer divergência de schema) pode ser modificado acidentalmente.

Três posturas foram avaliadas:

| Postura | Comportamento | Risco |
|---|---|---|
| `mergeSchema = true` | Aceita automaticamente novas colunas ao escrever | Mascaramento de mudanças breaking (renomeação de coluna gera nova coluna + antiga como nula, sem alerta) |
| `overwriteSchema = true` | Substitui o schema completo na escrita | Requer intervenção manual em cada ingestão com schema diferente; adequado para mudanças planejadas |
| Falha explícita com alerta | Pipeline interrompe ao detectar qualquer divergência de schema | Operacionalmente mais custoso; elimina ingestão silenciosa de dados malformados |

**Postura adotada: falha explícita com alerta na camada Bronze.**

O pipeline detecta divergência de schema antes da escrita, registra o diff entre o schema esperado (definido como referência no repositório) e o schema recebido (inferido do CSV da ANAC), e interrompe a execução com uma exceção descritiva. A promoção para Silver só ocorre após revisão da mudança e atualização explícita do schema de referência no repositório.

Essa postura é mais trabalhosa operacionalmente — toda mudança de schema na fonte ANAC requer intervenção explícita no pipeline antes de prosseguir. O benefício é compatível com o objetivo de portfólio: demonstra consciência de qualidade de dados e capacidade de detectar mudanças breaking antes que contaminem camadas downstream. Em um contexto de Pleno, essa é a postura defensável.

`mergeSchema = true` é conveniente para desenvolvimento local, mas perigosa em produção: uma renomeação de coluna na fonte gera duas colunas na tabela Delta (a antiga, agora nula, e a nova), sem nenhum alerta. O bug se propaga silenciosamente para Silver e Gold antes de ser detectado.

### Negativas

- A integração Delta Lake + GCS requer atenção à versão do `gcs-connector-hadoop3` disponível na imagem Dataproc e à configuração do SparkSession. Essa configuração não é necessária com Iceberg no mesmo ambiente.
- A postura de `schema evolution` por falha explícita aumenta o trabalho operacional em cada período de ingestão em que a ANAC publicar uma mudança de schema. Esse custo é deliberado.
- A dependência do `delta-spark` no Databricks (vendor único) é um risco de longo prazo ausente no Iceberg. Para este projeto de aprendizado, o risco é irrelevante; em projetos de produção com horizonte de anos, seria um critério de avaliação.
- Versões incompatíveis entre `delta-spark` e Spark da imagem Dataproc geram erros de classpath em runtime, não em tempo de compilação. A combinação de versões documentada nesta ADR precisa ser verificada contra a imagem efetivamente utilizada (`[VERIFICAR]`).

---

## Dependências

### Esta ADR depende de

| ADR | Dependência |
|---|---|
| ADR-00 | O constraint de $300 em créditos GCP elimina BigQuery como alternativa de storage. O objetivo de portfólio para vagas Pleno justifica `open table format` em vez de Parquet puro. |

**Co-dependência reconhecida com ADR-07 (Arquitetura Medalhão):** ADR-02 e ADR-07 foram tomadas simultaneamente durante o planejamento e se informam mutuamente. A escolha do Delta Lake pressupõe uma arquitetura de camadas (Bronze/Silver/Gold) que justifica ACID e time travel; a definição da arquitetura Medalhão pressupõe um `open table format` com garantias transacionais. Não há precedência entre as duas decisões — elas formam um par interdependente. A relação não é modelada como dependência unidirecional no grafo de ADRs para evitar ciclo.

### Esta ADR é dependência de

| ADR | Dependência |
|---|---|
| ADR-03 | O ambiente Spark no Dataproc precisa estar configurado com `delta-spark` na versão correta e com o `gcs-connector-hadoop3` acessível. A ADR-03 define a configuração do SparkSession e as propriedades do cluster Dataproc que viabilizam a leitura e escrita de tabelas Delta no GCS. |
| ADR-05 | A estratégia de qualidade de dados pressupõe assertions PySpark rodando sobre tabelas Delta na camada Silver. A garantia de que o dado na Silver passou por `schema enforcement` na Bronze — e que a promoção foi atômica — é a base sobre a qual as assertions da ADR-05 podem ser aplicadas com confiança. |

---

## Referências

- ADR-00: Contexto Global e Constraints do Projeto
- ADR-07: Arquitetura Medalhão (Bronze/Silver/Gold)
- [Delta Lake — Compatibility with Spark versions](https://docs.delta.io/latest/releases.html)
- [Delta Lake on Google Cloud Storage — community documentation](https://delta.io/blog/)
- [Apache Iceberg — Table Spec](https://iceberg.apache.org/spec/)
- [Dataproc — Available images and included components](https://cloud.google.com/dataproc/docs/concepts/versioning/overview)
- [gcs-connector-hadoop3 — Dataproc default configuration](https://cloud.google.com/dataproc/docs/concepts/connectors/cloud-storage)
