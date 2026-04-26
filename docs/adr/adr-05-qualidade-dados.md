# ADR-05: Estratégia de Qualidade de Dados — Assertions Nativas PySpark Integradas ao DAG Airflow

## Status

Proposta

> _Esta decisão foi tomada durante a fase de planejamento — nenhuma fase do projeto foi implementada. O status será revisado para `Aceita` após implementação e validação em ambiente real._

---

## Contexto

### O problema de qualidade de dados neste pipeline

O pipeline ingere estatísticas de transporte aéreo doméstico da ANAC a partir de CSVs mensais com histórico documentado de instabilidade de schema, variações de codificação e inconsistências nos valores publicados. A arquitetura Medalhão definida na ADR-07 pressupõe que a camada Silver só contém dados que passaram por critérios explícitos de promoção, e que a camada Gold só agrega dados cujos totais são consistentes com a Silver do mesmo período.

Esses critérios precisam ser implementados como código executável. A decisão que esta ADR registra é sobre *qual abordagem* usar para implementá-los: assertions nativas com a API PySpark padrão, ou um framework especializado de qualidade de dados.

### Qualidade de dados tem ferramentas especializadas estabelecidas

O mercado tem frameworks maduros para qualidade de dados — Great Expectations, Soda Core, dbt tests são os mais relevantes para este contexto. Cada um resolve o problema de validação com abstração própria, documentação própria e curva de aprendizado própria. A presença crescente desses frameworks em times de dados com requisitos de auditoria formal é real e não deve ser subestimada.

A questão não é se esses frameworks entregam valor em geral. É se entregam valor *neste projeto*, dado o objetivo declarado na ADR-00: aprendizado substantivo de PySpark e Airflow orientado ao mercado de vagas Engenheiro de Dados Pleno no Brasil.

### O histórico desta decisão — reversão do Great Expectations

Este ponto é parte central do registro histórico desta ADR e deve ser lido como tal.

Great Expectations estava no briefing original deste projeto como decisão tomada. Durante a fase de planejamento — antes de qualquer linha de código — a decisão foi revertida após análise de coerência com os objetivos declarados do projeto.

A reversão não foi uma falha de planejamento. Foi o raciocínio arquitetural funcionando como deveria: uma decisão anterior foi questionada com critérios explícitos, as razões foram analisadas, e o resultado foi uma escolha mais coerente com o contexto. Registrar esse histórico sem constrangimento é o propósito desta seção. Decisões que sobrevivem a questionamentos sérios chegam ao código com mais clareza e menos dívida técnica. Decisões revertidas no papel são superiores a decisões revertidas durante a implementação.

### Constraints que delimitam o espaço de soluções

Dois constraints documentados na ADR-00 são premissas diretas desta decisão:

1. **Foco em PySpark e Airflow como objetivo central de aprendizado**: adicionar um framework especializado de qualidade de dados introduz uma terceira tecnologia central no stack. O argumento de coerência — que já foi aplicado para rejeitar dbt — se aplica com a mesma força aqui.

2. **Constraint financeiro de $300 em créditos GCP**: qualquer fricção de integração que resulte em debugging prolongado tem custo real em tempo e créditos de free trial. Uma integração que funciona bem em ambientes convencionais mas exige configuração adicional no contexto específico de Delta Lake sobre GCS é um risco que o projeto não pode absorver de forma negligente.

---

## Decisão

**As validações de qualidade de dados são implementadas como assertions nativas PySpark, encapsuladas em funções Python, e integradas ao DAG Airflow como `@task` normais da TaskFlow API.**

Não há dependência de framework externo de qualidade de dados neste projeto.

Cada assertion é uma função Python que recebe um DataFrame Spark, executa uma verificação com a API padrão do PySpark — `df.filter()`, `.groupBy()`, `.agg()`, `.count()`, `.where()` — e retorna um resultado estruturado com `pass/fail`, contagem de registros afetados e descrição do problema quando `fail`. As funções de assertion são testáveis com `pytest` da mesma forma que qualquer outra transformação do pipeline.

A integração com o Airflow segue o mesmo padrão da TaskFlow API descrita na ADR-01: cada assertion vira uma `@task`, a falha da assertion é uma falha de task, e o comportamento de retry e alerta é o comportamento nativo do Airflow — sem configuração adicional de integração.

---

## Alternativas consideradas

### Great Expectations com checkpoints integrados ao Airflow

A alternativa mais séria que foi analisada — e que estava no briefing original como decisão tomada antes da reversão documentada na seção de Contexto.

**O que GX entrega que não pode ser minimizado:**

O Great Expectations gera relatórios HTML auditáveis (`Data Docs`) com histórico visual de execução de cada `checkpoint`. Para um portfólio que será avaliado por engenheiros externos, a capacidade de apontar para um relatório visual que mostra "o pipeline de outubro/2023 passou em 100% das expectations, o de novembro/2023 falhou na expectation X com Y registros afetados" é um diferencial concreto. A DSL expressiva das `expectations` — `expect_column_values_to_not_be_null()`, `expect_column_values_to_be_between()` — é legível por não-engenheiros e comunica intenção de qualidade de forma mais imediata do que código PySpark equivalente.

A presença crescente do GX no mercado em times com requisito de auditoria formal é real. Em um ambiente de produção com necessidade de relatórios de qualidade para stakeholders não-técnicos, GX seria a escolha defensável.

**Por que foi rejeitado — primeiro motivo: incoerência com o objetivo declarado**

O argumento que rejeitou o dbt — introdução de uma terceira tecnologia central no stack, diluindo o foco de aprendizado em PySpark e Airflow — se aplica ao GX com a mesma força. Aceitar GX após rejeitar dbt por essa razão seria incoerente. O critério precisa ser aplicado de forma consistente, ou deixa de ser um critério.

O Great Expectations tem DSL própria, modelo mental próprio (`expectations`, `expectation suites`, `checkpoints`, `data sources`, `batch requests`) e curva de aprendizado real. Operar o GX com a profundidade necessária para integrá-lo corretamente ao Airflow e ao Delta Lake consome tempo de aprendizado que, neste projeto, é intencionalmente alocado para PySpark e Airflow. Demonstrar GX em portfólio é um diferencial real — mas é um diferencial diferente do que este projeto se propõe a demonstrar.

**Por que foi rejeitado — segundo motivo: fricção técnica real com Delta Lake sobre GCS**

Este motivo é técnico e específico ao contexto deste projeto. O GX não lê tabelas Delta diretamente. Para validar dados em uma tabela Delta, há duas abordagens:

- Carregar o DataFrame Spark manualmente e passá-lo para o contexto do GX via `RuntimeDataConnector` ou `SparkDFDataset` — o que funciona, mas exige que o SparkSession e o contexto do GX sejam configurados de forma compatível no ambiente Dataproc;
- Apontar para os arquivos Parquet subjacentes às tabelas Delta no GCS — o que ignora o `_delta_log` e pode resultar em leitura de arquivos que o Delta Lake considera logicamente deletados após uma operação de `VACUUM`.

Nenhuma das duas abordagens é trivial no contexto específico de Dataproc + Delta Lake + GCS. O risco de consumir horas de debugging e créditos do free trial configurando a integração — ao invés de avançar no desenvolvimento do pipeline — foi avaliado como inaceitável para os objetivos do projeto. É um risco real, não uma estimativa conservadora: a documentação do GX sobre integração com Delta Lake e GCS é escassa em comparação com a documentação de integração com S3 e Databricks.

A combinação dos dois motivos — incoerência com o objetivo declarado e fricção técnica específica ao contexto — tornou a reversão da decisão original a escolha mais defensável. O primeiro motivo sozinho já seria suficiente. O segundo elimina qualquer ambiguidade residual.

---

### dbt tests

Rejeitado antes de entrar na análise de trade-offs.

O dbt introduziria uma terceira tecnologia central no stack — ao lado de PySpark e Airflow — sem benefício que justifique esse custo dentro do escopo deste projeto. Os testes do dbt são escritos como queries SQL executadas pelo próprio dbt, o que pressupõe o dbt como ferramenta de transformação. Adotar dbt apenas para os testes, sem usar dbt para as transformações, não é um padrão de uso natural e introduziria a complexidade de integração sem o benefício de aprendizado de dbt como ferramenta de transformação.

A rejeição segue exatamente o mesmo critério aplicado ao GX: coerência com o foco declarado do projeto.

---

### Soda Core

O Soda Core tem sintaxe de definição de checks mais simples do que o GX — arquivos `.yaml` com checks declarativos (`row_count > 0`, `missing_count(campo) = 0`) de leitura imediata. A curva de aprendizado é menor.

Rejeitado por dois motivos combinados:

Primeiro: a integração nativa com Airflow é menos consolidada do que a do GX. O `GreatExpectationsOperator` é mantido pelo projeto `apache-airflow-providers-great-expectations`; o equivalente para Soda Core tem menos presença em documentação e tutoriais, o que aumenta o risco de fricção de integração.

Segundo: menor presença no mercado brasileiro de engenharia de dados. Se o argumento de visibilidade de portfólio não foi suficiente para manter o GX — que tem presença de mercado superior — não seria suficiente para adotar o Soda Core em seu lugar.

---

### Assertions manuais ad-hoc em Python

Validações escritas como blocos Python soltos, fora de qualquer estrutura de task no DAG, sem registro sistemático de resultado.

Rejeitadas por um motivo operacional direto: uma validação que existe fora do DAG pode ser pulada, reordenada ou simplesmente omitida em uma manutenção futura sem que o pipeline registre a omissão como falha. Em um pipeline de portfólio onde a rastreabilidade operacional é um critério de avaliação, isso é inaceitável.

A diferença entre uma assertion ad-hoc e uma assertion encapsulada como `@task` é a diferença entre uma validação que pode ser esquecida e uma validação que, se omitida, quebra o DAG. As assertions ad-hoc são adequadas para debug local; são inadequadas como estratégia de qualidade de dados em um pipeline documentado.

---

## Consequências

### O que assertions nativas PySpark entregam neste projeto

**Reforço do aprendizado central, não diversificação.** Cada assertion é escrita com a API PySpark padrão — `df.filter()`, `.groupBy()`, `.agg()`, `.count()`. Escrever validações de qualidade em PySpark reforça o mesmo conjunto de operações que o pipeline usa para transformação de dados. Não há DSL nova para aprender, não há modelo mental adicional para internalizar. O código de validação e o código de transformação compartilham a mesma base de conhecimento.

**Integração zero-config com o Airflow.** As assertions são `@task` normais no DAG. A TaskFlow API descrita na ADR-01 trata uma assertion exatamente da mesma forma que trata uma transformação Spark ou uma chamada de operador Dataproc — nenhuma configuração adicional de integração, nenhum operador customizado, nenhuma dependência de biblioteca externa. Uma assertion que falha é uma task que falha, com retry configurado via `retries` e `retry_delay` do próprio Airflow.

**Testabilidade com `pytest`.** Uma função de assertion PySpark é uma função Python que recebe um DataFrame e retorna um resultado — testável unitariamente com `pytest` e uma SparkSession local. Isso não é possível com assertions definidas em arquivos `.yaml` de frameworks externos sem instanciar o framework completo no ambiente de teste.

**Comportamento nativo de falha no Airflow.** Quando uma assertion falha, a task correspondente falha. O histórico de execuções do Airflow registra qual assertion falhou, em qual execução, com qual mensagem de erro. O retry automático configura-se via `retries` na `@task`. Os alertas por email ou Slack usam os mesmos mecanismos de notificação já configurados para o DAG. Nenhuma infraestrutura adicional de alerta é necessária para as assertions de qualidade.

---

### Em quais camadas as assertions são aplicadas

A estratégia de cobertura é deliberada e assimétrica. A semântica de cada camada é definida na ADR-07 — esta seção documenta como as assertions se posicionam dentro dessa semântica, não a redefine.

#### Bronze — sem assertions

A camada Bronze preserva o dado raw exatamente como recebido da ANAC. Nenhuma assertion é aplicada aqui, e isso é comportamento correto, não uma lacuna.

Rejeitar dados na Bronze — antes de entender a natureza do problema — introduz o risco de descartar informação que seria recuperável com tratamento na Silver. A Bronze é a fonte da verdade para reprocessamento: se um dado foi publicado pela ANAC, ele existe na Bronze. A responsabilidade de decidir o que fazer com esse dado — promover, transformar, ou colocar em quarentena — pertence à Silver.

O `schema enforcement` do Delta Lake descrito na ADR-02 opera na Bronze, mas em sentido diferente das assertions de qualidade: ele rejeita arquivos com schema estruturalmente incompatível, não registros individuais com valores problemáticos. Essa distinção é relevante — o Delta Lake protege a integridade estrutural da tabela; as assertions da Silver protegem a qualidade dos registros.

#### Silver — assertions de integridade e consistência

As assertions da Silver são executadas como `@task` no DAG imediatamente antes da promoção dos dados limpos. Um registro que falha em qualquer assertion da Silver não é promovido — vai para a tabela de quarentena descrita na ADR-07 com `rejection_reason` preenchido.

Assertions aplicadas na promoção Bronze → Silver:

- **Ausência de nulos em campos obrigatórios**: `sg_empresa`, `cd_origem`, `cd_destino`, `ano_referencia`, `mes_referencia` não podem ser nulos. Uma linha com qualquer desses campos nulo não tem identidade suficiente para ser um registro válido.
- **Tipos corretos após casting**: campos numéricos (`passageiros_pagos`, `passageiros_gratis`, `carga_paga_kg`, etc.) devem ser castáveis para seus tipos sem produzir `null` por falha de conversão. Campos de data devem ser parseáveis no formato esperado.
- **Valores dentro de domínios esperados**: valores numéricos que representam contagens ou pesos não podem ser negativos. Códigos de aeroporto devem ter o formato esperado (2–4 caracteres alfanuméricos). `ano_referencia` e `mes_referencia` devem ser coerentes com o período de referência declarado no nome do arquivo de origem.
- **Ausência de duplicatas no período**: a combinação `(ano_referencia, mes_referencia, sg_empresa, cd_origem, cd_destino)` deve ser única dentro do lote do período. Duplicatas dentro do mesmo arquivo da ANAC são registradas e descartadas, não promovidas.

`[VERIFICAR]` — a lista completa de campos obrigatórios e os domínios de validação precisam ser confirmados contra o schema real do CSV da ANAC durante a fase de implementação. Os campos listados acima refletem o schema documentado publicamente e são os mais prováveis de permanecerem estáveis, mas o dataset da ANAC tem histórico de variação.

#### Gold — assertions de negócio

As assertions da Gold são executadas como `@task` no DAG após a agregação e antes de disponibilizar os dados para consumo. Uma falha nas assertions da Gold indica problema na agregação ou inconsistência com a Silver — não um problema de dado individual.

Assertions aplicadas na promoção Silver → Gold:

- **Totais agregados consistentes com a Silver**: o somatório de `passageiros_pagos` na tabela Gold para um período de referência não pode ser maior que o somatório da coluna equivalente na Silver para o mesmo período. A Gold é uma projeção agregada da Silver — ela não pode conter mais informação do que a fonte.
- **Variações entre períodos dentro de limites históricos**: uma queda ou aumento superior a 30% nos totais agregados entre períodos consecutivos — sem evento externo documentado (ex: pandemia, regulação, fechamento de rota) — deve gerar falha na assertion com mensagem descritiva, não ser promovida silenciosamente. `[VERIFICAR]` — o percentual de variação tolerado precisa ser calibrado após as primeiras execuções reais com dados históricos, conforme também sinalizado na ADR-07.
- **Contagem de rotas distintas não nula**: a tabela Gold de rotas por período deve conter pelo menos uma linha após a agregação. Uma agregação que produz zero linhas para um período com dados na Silver indica bug na lógica de agregação.

---

### Rastreabilidade de qualidade — tabela `gold.data_quality_metrics`

**Esta abordagem é recomendada e deve ser implementada.**

A objeção mais legítima à estratégia de assertions nativas — em comparação com o Great Expectations — é a ausência de relatórios visuais de qualidade. Os `Data Docs` do GX geram um histórico visual de execução que permite responder "o pipeline de outubro/2023 passou em todas as expectations?" de forma imediata, sem escrever uma query. Esse diferencial de portfólio é real e foi documentado honestamente na seção de Alternativas consideradas.

A resposta a essa objeção não é ignorá-la — é endereçá-la dentro dos constraints do projeto. A abordagem adotada: cada assertion persiste seu resultado em uma tabela Delta dedicada na camada Gold.

**Estrutura da tabela `gold.data_quality_metrics`:**

| Coluna | Tipo | Descrição |
|---|---|---|
| `execution_date` | `TimestampType` | Timestamp da execução da assertion no DAG |
| `pipeline_layer` | `StringType` | Camada onde a assertion foi executada: `"Silver"` ou `"Gold"` |
| `assertion_name` | `StringType` | Identificador da assertion executada (ex: `"silver_no_nulls_campos_obrigatorios"`) |
| `result` | `StringType` | `"pass"` ou `"fail"` |
| `records_affected` | `LongType` | Contagem de registros que falharam na validação; 0 para `result = "pass"` |
| `details` | `StringType` | Descrição textual do problema quando `result = "fail"`; `null` quando `result = "pass"` |

**Por que essa abordagem é recomendada:**

Primeiro: entrega rastreabilidade histórica de qualidade sem introduzir nenhuma dependência nova. A tabela `gold.data_quality_metrics` é uma tabela Delta como qualquer outra no projeto — escrita com a mesma API PySpark, armazenada no mesmo GCS, lida com a mesma SparkSession. Sem biblioteca adicional, sem serviço adicional, sem custo de configuração.

Segundo: uma query simples sobre a tabela é funcionalmente equivalente ao `Data Doc` do GX para responder "o pipeline de X passou em todas as assertions?":

```python
df_quality = spark.read.format("delta").load("gs://bucket/gold/data_quality_metrics")
df_quality.filter(
    (F.col("execution_date") >= "2023-10-01") &
    (F.col("execution_date") < "2023-11-01")
).groupBy("result").count().show()
```

O resultado é auditável, reproduzível e não requer interface visual para ser útil.

Terceiro: o padrão de gravar métricas operacionais em uma tabela dedicada é reconhecível por engenheiros que avaliarão o portfólio. Demonstra pensamento sobre observabilidade dentro dos constraints do projeto — não como afterthought, mas como decisão arquitetural explícita.

Quarto: a tabela `gold.data_quality_metrics` não contradiz a decisão de não usar GX. A rastreabilidade é implementada com as ferramentas já presentes no stack, pelo mesmo time que implementa o pipeline. Sem dependência adicional, sem curva de aprendizado adicional, sem ponto de falha adicional.

---

### Consequências negativas

**Ausência de relatórios visuais nativos.** Não há geração automática de relatórios HTML como os `Data Docs` do GX. Um stakeholder não-técnico que precise avaliar a qualidade dos dados não encontra uma interface visual imediata. O `gold.data_quality_metrics` mitiga parcialmente essa ausência — mas é uma tabela que requer query, não um relatório pronto. Em um projeto de produção com stakeholders não-técnicos, essa ausência seria um critério de avaliação real. Neste projeto, a ausência é um trade-off documentado, não uma lacuna não reconhecida.

**Sem DSL de expectations.** O código de assertion em PySpark é mais verboso do que a equivalente em Great Expectations. `df.filter(F.col("sg_empresa").isNull()).count() > 0` é menos imediato do que `expect_column_values_to_not_be_null("sg_empresa")` para um leitor sem contexto de PySpark. Esse custo de legibilidade é real, mas é compensado pelo valor de demonstrar as operações PySpark que compõem a validação — o código de assertion é, simultaneamente, código de demonstração da API PySpark.

**Manutenção das assertions como responsabilidade explícita do time.** Frameworks como GX têm suites de expectations gerenciadas com versionamento próprio. As assertions nativas PySpark neste projeto são código Python como qualquer outro — sem mecanismo especializado de gestão de versão das regras de qualidade. Em escala maior, isso se torna um ponto de atenção. No escopo deste projeto, a simplicidade compensa.

---

## Dependências

### Esta ADR depende de

| ADR | Dependência |
|---|---|
| ADR-01 | As assertions são `@task` no DAG Airflow com TaskFlow API. A integração pressupõe a escolha do Airflow como orquestrador e o padrão de autoria de DAGs documentado na ADR-01. |
| ADR-02 | As assertions da Silver rodam sobre tabelas Delta lidas como DataFrame Spark. A garantia de que o dado na Silver passou por `schema enforcement` na Bronze — e que a promoção foi atômica via ACID transactions — é a base sobre a qual as assertions podem ser aplicadas com confiança. |
| ADR-07 | A arquitetura Medalhão define em quais camadas aplicar assertions e qual a semântica de cada camada. A decisão de não aplicar assertions na Bronze, aplicar assertions de integridade na Silver e assertions de negócio na Gold é uma consequência direta da semântica das camadas definida na ADR-07, não uma decisão independente. |

### Esta ADR não é dependência de nenhuma outra ADR

A estratégia de qualidade de dados é terminal no grafo de dependências — nenhuma outra decisão arquitetural do projeto depende desta ADR para ser tomada.

---

## Referências

- ADR-00: Contexto Global e Constraints do Projeto
- ADR-01: Orquestrador de Pipelines — Apache Airflow 2.8 com TaskFlow API
- ADR-02: Formato de Armazenamento — Delta Lake sobre GCS
- ADR-07: Arquitetura de Camadas do Pipeline — Padrão Medalhão (Bronze/Silver/Gold)
- [Apache Spark — DataFrame API (PySpark)](https://spark.apache.org/docs/latest/api/python/reference/pyspark.sql/dataframe.html)
- [Great Expectations — Integrating with Apache Spark](https://docs.greatexpectations.io/docs/deployment_patterns/how_to_use_great_expectations_with_pyspark/)
- [Great Expectations — Airflow and Great Expectations](https://docs.greatexpectations.io/docs/deployment_patterns/how_to_use_great_expectations_in_airflow/)
- [Soda Core — Documentation](https://docs.soda.io/soda-core/overview-main.html)
- [ANAC — Dados Estatísticos do Transporte Aéreo](https://www.anac.gov.br/assuntos/dados-e-estatisticas/dados-estatisticos)
