# ADR-07: Arquitetura de Camadas do Pipeline — Padrão Medalhão (Bronze/Silver/Gold)

## Status

Proposta

> _Esta decisão foi tomada durante a fase de planejamento — nenhuma fase do projeto foi implementada. O status será revisado para `Aceita` após implementação e validação em ambiente real._

---

## Contexto

O pipeline ingere estatísticas de transporte aéreo doméstico brasileiro publicadas pela ANAC em formato CSV mensal. Cada arquivo representa um mês de operações, com dados de rotas, companhias aéreas, aeroportos, passageiros transportados e carga. A frequência de atualização é mensal, o volume é gerenciável em um único job Spark, e não há requisito de processamento em tempo real — nem na especificação funcional do projeto, nem na natureza do dado publicado pela ANAC.

Nesse cenário, a decisão sobre arquitetura de camadas determina:

- Como o dado raw é preservado para auditoria e reprocessamento
- Onde as transformações e validações de qualidade são aplicadas
- Como as responsabilidades são separadas entre etapas do pipeline
- Quais garantias existem em caso de bug introduzido em qualquer etapa de transformação

Dois constraints documentados na ADR-00 são premissas diretas desta decisão:

1. **Constraint de custo**: o projeto opera com $300 em créditos GCP (`free trial`). Qualquer arquitetura que exija infraestrutura de streaming ativa (Dataflow, Pub/Sub, Kafka gerenciado) é incompatível com esse orçamento.
2. **Ausência de requisito de streaming**: o dataset da ANAC é batch por natureza. Não há fonte de eventos em tempo real, não há SLA de latência que exija processamento em menos de horas, e não há caso de uso que se beneficie de uma speed layer.

Além dos constraints, o pipeline utiliza Delta Lake como formato de armazenamento (decisão documentada na ADR-02). As features do Delta Lake — ACID transactions, time travel e schema enforcement — têm relação direta com a viabilidade operacional da arquitetura de camadas escolhida, como detalhado na seção de Decisão.

---

## Decisão

Adotar o padrão **Medalhão** com três camadas semânticas — **Bronze**, **Silver** e **Gold** — cada uma com responsabilidade definida e critérios objetivos de promoção entre elas.

### Definição das camadas no contexto do dataset ANAC

#### Camada Bronze

A camada Bronze é a zona de ingestão. O CSV recebido da ANAC é escrito no Delta Lake sem nenhuma transformação de conteúdo — campos, valores e estrutura são preservados exatamente como publicados. A única adição são colunas de auditoria anexadas no momento da ingestão:

- `ingestion_date`: timestamp da execução do job de ingestão
- `source_file`: nome do arquivo CSV de origem (ex.: `resumo_anual_2023_01.csv`)

A camada Bronze é a **fonte da verdade para reprocessamento**. Se um bug é introduzido na transformação Silver, o dado pode ser reprocessado integralmente a partir da Bronze sem re-ingerir da fonte ANAC. Essa garantia só existe se a Bronze nunca for modificada retroativamente — o schema enforcement do Delta Lake impede ingestões que violem a estrutura estabelecida, e o time travel preserva versões anteriores.

Nenhuma validação de qualidade, remoção de duplicatas ou conversão de tipos ocorre na Bronze. O dado ruim publicado pela ANAC entra na Bronze exatamente como está — e isso é o comportamento correto: a Bronze deve espelhar a fonte, não corrigi-la.

#### Camada Silver

A camada Silver é a zona de dado limpo, tipado e validado. Um registro existe na Silver se — e somente se — passou pelo conjunto de critérios definidos na promoção Bronze → Silver:

- Não é duplicata dentro do período de referência mensal
- Todos os campos obrigatórios estão presentes e não nulos (ex.: código do aeroporto de origem, código do aeroporto de destino, código ICAO da companhia aérea, ano e mês de referência)
- Os campos são castáveis para seus tipos corretos sem perda de informação: datas convertidas para `DateType`, campos numéricos para `IntegerType` ou `DoubleType` conforme o campo, categóricos normalizados para `StringType`
- O registro passa nas assertions de qualidade configuradas (documentadas na ADR-05): valores numéricos dentro de intervalos válidos, códigos de aeroporto presentes na tabela de referência ANAC, ausência de combinações impossíveis de campos

As transformações aplicadas na Silver incluem:

- Remoção de duplicatas por período de referência
- Casting de tipos com tratamento explícito de falhas de conversão
- Padronização de campos categóricos: normalização de nomes de companhias aéreas (variações históricas de grafia), padronização de códigos de aeroporto (IATA vs. ICAO onde há ambiguidade no CSV)
- Registro de linhas rejeitadas em tabela de quarentena para auditoria posterior

A Silver não agrega. Ela não calcula métricas. Ela entrega um dataset de linhas individuais limpo, tipado e confiável para a etapa seguinte.

#### Camada Gold

A camada Gold é a zona de consumo analítico. Ela recebe os dados validados da Silver e produz agregações prontas para consulta: métricas por rota, por companhia aérea, por período (mensal e trimestral), por aeroporto de origem e destino.

As tabelas Gold são otimizadas para os padrões de consulta esperados: particionadas por `ano` e `mes` de referência, com colunas de alta cardinalidade em posição favorável para predicate pushdown.

Nenhuma lógica de limpeza, validação ou remoção de duplicatas ocorre na Gold. Se a Gold produz um resultado incorreto, o problema está na Silver ou na Bronze — a Gold apenas agrega o que recebe.

### Critérios objetivos de promoção entre camadas

**Bronze → Silver**: um registro é promovido se cumprir simultaneamente:

1. Não é duplicata identificada pela chave `(ano_referencia, mes_referencia, sg_empresa, cd_origem, cd_destino)` dentro do período de referência já processado
2. Os campos `sg_empresa`, `cd_origem`, `cd_destino`, `ano_referencia` e `mes_referencia` estão presentes e não nulos
3. Os campos numéricos (`passageiros_pagos`, `passageiros_gratis`, `carga_paga_kg`, `carga_gratis_kg`, `correio_kg`, `ask`, `rpk`, `atk`, `rtk`) são castáveis para seus tipos sem produzir `null` por falha de conversão
4. O registro passa nas assertions configuradas na ADR-05

Registros que falham em qualquer critério são gravados na tabela de quarentena Silver com a coluna `rejection_reason` preenchida. Eles não bloqueiam a promoção dos demais registros do lote.

**Silver → Gold**: a agregação de um período de referência é executada se:

1. O período de referência tem ingestão completa — o arquivo mensal correspondente foi processado e o job de ingestão concluiu com status de sucesso registrado nos metadados do pipeline
2. A contagem de registros Silver para o período está dentro dos limites históricos esperados — variação superior a 30% em relação à mediana dos últimos seis períodos sinaliza possível erro de upstream e bloqueia a promoção até revisão manual [VERIFICAR: percentual de variação tolerado — ajustar conforme comportamento histórico real do dataset]

### Relação com Delta Lake

O padrão Medalhão, como definido acima, pressupõe três garantias que o Delta Lake fornece:

- **ACID transactions**: a promoção de registros da Bronze para a Silver é uma operação atômica. Leitores concorrentes nunca veem um estado intermediário em que parte dos registros de um período já foi promovida e parte ainda não.
- **Time travel**: qualquer camada pode ser reprocessada a partir de uma versão anterior sem re-ingerir da fonte. Se um bug de transformação é descoberto na Silver, o reprocessamento parte da Bronze sem depender de disponibilidade do endpoint da ANAC ou de re-download do CSV original. Isso é especialmente relevante para datasets com histórico de alterações retroativas nos arquivos publicados.
- **Schema enforcement**: a Bronze recusa ingestões que violem o schema estabelecido. Quando a ANAC altera o schema do CSV — comportamento documentado no histórico do dataset — o pipeline falha explicitamente na ingestão em vez de aceitar silenciosamente um dado com estrutura diferente. A estratégia de schema evolution para lidar com essas alterações é documentada na ADR-02.

A relação é de habilitação: o Medalhão define a semântica das camadas e as responsabilidades de cada etapa; o Delta Lake fornece as garantias transacionais e de rastreabilidade que tornam essa semântica operacionalmente confiável.

---

## Alternativas consideradas

### Arquitetura Lambda

A arquitetura Lambda mantém dois caminhos paralelos de processamento: uma batch layer para reprocessamento histórico e uma speed layer para ingestão em tempo real de baixa latência. A merge view combina os resultados de ambas para o consumidor.

A rejeição para este projeto tem duas razões técnicas independentes, qualquer uma delas suficiente por si só:

**Ausência total de requisito de streaming.** O dataset da ANAC é publicado mensalmente em CSV. Não existe fonte de eventos em tempo real para alimentar uma speed layer. Não há Kafka, não há Pub/Sub, não há endpoint de streaming da ANAC. Construir uma speed layer sem dado em tempo real é infraestrutura sem caso de uso — não um trade-off aceitável, mas uma construção sem propósito no contexto deste projeto.

**Incompatibilidade com o constraint de $300.** A infraestrutura de streaming necessária para uma speed layer operacional no GCP — Dataflow para processamento de stream, Pub/Sub como broker de mensagens — teria custo mensal incompatível com o orçamento total do projeto documentado na ADR-00. Essa rejeição não é preferência técnica: é inviabilidade financeira objetiva.

O argumento usual a favor de Lambda — que ele permite servir dados com latência de segundos enquanto o batch reprocessa o histórico — é irrelevante aqui. Um analista que consulta estatísticas mensais de voos domésticos não tem SLA de segundos. A latência aceitável é de horas ou dias, alinhada com a frequência de atualização mensal da fonte.

### Arquitetura Kappa

A arquitetura Kappa unifica batch e streaming em um único caminho de processamento via stream replay. Em vez de manter dois sistemas separados como o Lambda, o Kappa reprocessa dados históricos relendo eventos do log de stream — o que simplifica a operação ao custo de exigir que todo processamento seja expresso como transformação de stream.

A rejeição é mais direta que a do Lambda: sem fonte de streaming, o Kappa não tem onde se apoiar. O mecanismo de reprocessamento histórico via stream replay — que é a contribuição arquitetural central do Kappa em relação ao Lambda — é substituído neste projeto pelo time travel do Delta Lake, sem necessidade de infraestrutura de stream. A Bronze preservada no Delta Lake com versionamento é o equivalente funcional do log de eventos do Kappa para o caso de uso de reprocessamento batch.

### Arquitetura flat (sem camadas)

Uma arquitetura flat processa o dado em uma única passagem: ingere o CSV da ANAC, aplica transformações, produz o resultado analítico. Sem camadas intermediárias persistidas.

Os problemas dessa abordagem para este projeto são concretos, não teóricos:

**Reprocessamento seletivo inviável.** Sem uma camada Bronze preservada como ponto de partida, reprocessar apenas a etapa de limpeza (equivalente à Silver) exige re-ingerir da fonte ANAC — o que depende de disponibilidade do endpoint e de o arquivo original ainda estar disponível no mesmo estado. Para um dataset com histórico de alterações retroativas nos arquivos publicados, essa dependência é um risco operacional real.

**Auditoria retroativa impossível.** Se um bug na lógica de transformação produz dados incorretos na camada de consumo, a ausência de dado raw preservado impede comparar o estado original com o estado processado. Não há como responder "o dado estava errado na fonte ou erramos na transformação?" sem a Bronze como referência.

**Ausência de contrato de qualidade.** Sem camadas definidas, não há ponto claro onde aplicar validações. As assertions de qualidade documentadas na ADR-05 pressupõem uma camada Silver com critérios de promoção explícitos. Em uma arquitetura flat, a validação teria que ser aplicada inline na única passagem de transformação — o que mistura responsabilidades e dificulta a separação entre "dado rejeitado" e "erro de transformação".

O argumento a favor de uma arquitetura flat seria simplicidade operacional. Para um dataset de baixo volume com transformações simples, isso tem peso real. A contra-argumentação é que a complexidade adicionada pelo Medalhão neste projeto é baixa — são três jobs Spark em vez de um — e os benefícios de auditabilidade e reprocessamento seletivo compensam esse custo mesmo em escala de portfólio.

---

## Consequências

### Positivas

- A camada Bronze como fonte da verdade imutável elimina dependência de disponibilidade contínua do endpoint da ANAC para reprocessamento. Dados históricos podem ser reprocessados integralmente a partir do que já foi ingerido.
- A separação entre dado raw (Bronze), dado validado (Silver) e dado agregado (Gold) cria contratos claros entre etapas do pipeline. Um bug na lógica de agregação não contamina os dados validados da Silver.
- A camada de quarentena na promoção Bronze → Silver torna rejeições auditáveis e rastreáveis, em vez de silenciosas. Registros rejeitados não desaparecem — ficam disponíveis para revisão com o motivo de rejeição explicitado.
- O padrão Medalhão é amplamente reconhecido no mercado brasileiro de engenharia de dados, o que contribui para o objetivo de portfólio documentado na ADR-00.

### Negativas

- Três camadas significam três jobs Spark distintos por ciclo de processamento, com o overhead de cold start do cluster Dataproc efêmero aplicado a cada um. O custo operacional por execução completa do pipeline é maior do que uma arquitetura flat. Esse custo é aceitável dado o constraint de volume (dataset mensal gerenciável) e o objetivo de aprendizado que justifica a operação do Dataproc.
- A definição de critérios de promoção Bronze → Silver exige conhecimento do schema do CSV da ANAC, que tem histórico de variações. Qualquer alteração no schema que quebre os critérios de promoção requer atualização explícita da lógica Silver — o que é trabalho de manutenção deliberado, não comportamento emergente.
- O critério de promoção Silver → Gold baseado em variação histórica de contagem de registros [VERIFICAR] requer calibração após os primeiros ciclos de execução real. Na fase de planejamento, o limiar de 30% é uma estimativa conservadora que pode precisar de ajuste.

---

## Dependências

**Esta ADR depende de:**

| ADR | Decisão | Relação |
|-----|---------|---------|
| ADR-00 | Contexto global e constraints | Os constraints de custo ($300) e a ausência de requisito de streaming documentados na ADR-00 são premissas diretas que justificam a rejeição de Lambda e Kappa |

**Co-dependência reconhecida — ADR-07 e ADR-02:**

ADR-07 (arquitetura Medalhão) e ADR-02 (Delta Lake como formato de armazenamento) foram tomadas em conjunto durante o planejamento e se informam mutuamente. A escolha do padrão Medalhão pressupõe as features ACID, time travel e schema enforcement que o Delta Lake fornece; a escolha do Delta Lake como formato de armazenamento pressupõe a existência das camadas Bronze, Silver e Gold que estruturam o pipeline. Não há precedência entre as duas decisões — elas formam um par interdependente e devem ser lidas em conjunto. Não é possível representar essa relação como aresta direcional sem criar uma dependência circular no grafo de ADRs.

**Esta ADR é dependência de:**

| ADR | Decisão | Dependência desta ADR |
|-----|---------|----------------------|
| ADR-05 | Qualidade de dados (assertions PySpark) | A estratégia de assertions precisa saber em quais camadas as validações são aplicadas. Os critérios de promoção Bronze → Silver definidos aqui são o contrato que a ADR-05 implementa |

---

## Referências

- ADR-00: Contexto Global e Constraints do Projeto
- ADR-02: Formato de Armazenamento (Delta Lake)
- ADR-05: Estratégia de Qualidade de Dados
- Databricks. *Medallion Architecture*. https://www.databricks.com/glossary/medallion-architecture
- Delta Lake. *ACID Transactions*. https://delta.io/
- ANAC. *Dados Estatísticos do Transporte Aéreo*. https://www.anac.gov.br/assuntos/dados-e-estatisticas/dados-estatisticos
