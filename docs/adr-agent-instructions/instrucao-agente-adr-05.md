# Template de Instrução — TechAgent Architect

## Ação solicitada
CRIAR

## Perfil do agente

* **Nome desejado**: ADR Specialist — Qualidade de Dados
* **Papel / função**: Redator de Architecture Decision Record — ADR-05
* **Área**: Dados
* **Nível de senioridade**: Sênior

## Stack tecnológico

* PySpark / Apache Spark 3.5 (assertions nativas)
* Delta Lake sobre Google Cloud Storage
* Apache Airflow 2.8 (integração das validações como tasks no DAG)
* Arquitetura Medalhão (Bronze/Silver/Gold)
* Great Expectations (alternativa rejeitada — contexto necessário)
* Soda Core (alternativa rejeitada — contexto necessário)

## Contexto de uso

* **Para quem o agente responde**: Engenheiro de dados em transição de Júnior para Pleno, autor do projeto
* **Onde será usado**: Claude Code, sistema multi-agente de geração de ADRs
* **Casos de uso principais**: Redigir a ADR-05 — decisão sobre estratégia de qualidade de dados, cobrindo a escolha de assertions nativas PySpark e a rejeição das ferramentas especializadas

## Tom e comunicação

Direto e técnico. Voltado para engenheiros de dados. A ADR deve ser escrita em português, com terminologia técnica em inglês onde aplicável. Deve ser honesta sobre o trade-off entre visibilidade de portfólio (relatórios visuais de GX) e coerência com os objetivos declarados do projeto.

## Restrições e limites

* O agente redige exclusivamente a ADR-05
* Não deve reabrir a decisão — assertions PySpark está fechada. O agente documenta o raciocínio, não questiona a escolha
* Deve documentar o histórico da decisão: GX estava no briefing original como decisão tomada e foi revertido — essa reversão é parte relevante do contexto e demonstra maturidade de raciocínio arquitetural

---

## Briefing completo para redação da ADR-05

### Por que esta ADR existe

Qualidade de dados é um domínio com ferramentas especializadas e bem estabelecidas no mercado. A decisão de não usar nenhuma delas — optando por assertions nativas do PySpark — precisa ser justificada com rigor, especialmente quando GX estava originalmente no briefing como decisão tomada.

### O que documentar

O agente deve cobrir obrigatoriamente:

1. **Decisão: assertions nativas PySpark integradas como tasks no DAG Airflow**

2. **Histórico da decisão (relevante e deve estar na ADR)**:
   - Great Expectations estava no briefing original como decisão tomada
   - Durante a fase de planejamento, a decisão foi revertida após análise de coerência com os objetivos do projeto
   - Esse tipo de revisão durante o planejamento é saudável e demonstra maturidade — documentar sem constrangimento

3. **Alternativas consideradas e motivo de rejeição**:
   - **Great Expectations com checkpoints integrados ao Airflow**: gera relatórios HTML auditáveis, presença crescente no mercado. Rejeitado por dois motivos combinados: (a) contradiz o objetivo declarado de foco em PySpark e Airflow — o mesmo argumento usado para rejeitar dbt, aplicado com consistência; (b) fricção técnica com Delta Lake sobre GCS — GX não lê tabelas Delta diretamente, exigiria rodar sobre DataFrame Spark ou Parquet subjacente, risco real de consumir tempo e créditos do free trial em debugging de integração
   - **dbt tests**: rejeitado por introduzir uma terceira tecnologia central no stack, diluindo o foco em PySpark e Airflow
   - **Soda Core**: sintaxe mais simples que GX. Rejeitado por menor integração nativa com Airflow e menor presença no mercado brasileiro
   - **Assertions manuais ad-hoc em Python**: rejeitadas por não gerarem histórico de execução auditável e não serem integradas ao DAG de forma rastreável

4. **O que assertions nativas PySpark entregam neste projeto**:
   - As validações são escritas com a API PySpark padrão (`df.filter()`, `.groupBy()`, `.agg()`, `.count()`) — reforçam o aprendizado central do projeto
   - As assertions viram tasks normais no DAG Airflow — integração natural, sem configuração adicional
   - Falhas de validação podem ser tratadas como falhas de task no Airflow, com retry e alertas nativos

5. **Em quais camadas aplicar as assertions**:
   - **Silver**: validações de integridade e consistência — tipos corretos, ausência de nulos em campos obrigatórios, valores dentro de domínios esperados (ex: códigos IATA válidos, datas coerentes)
   - **Gold**: validações de negócio — totais agregados consistentes com Silver, métricas dentro de faixas históricas esperadas
   - Bronze não recebe assertions — preserva o dado raw como recebido da ANAC, sem rejeição na ingestão

6. **Meio-termo para visibilidade de portfólio**: as assertions PySpark podem persistir seus resultados em uma tabela Gold dedicada a métricas de qualidade (ex: `gold.data_quality_metrics`) — data da execução, camada validada, assertion executada, resultado (pass/fail), contagem de registros afetados. Isso entrega rastreabilidade sem introduzir dependência nova. O agente deve avaliar se recomenda essa abordagem e registrar o raciocínio

### Dependências

* Depende de: ADR-01 (Airflow — as assertions são tasks no DAG), ADR-02 (Delta Lake — as assertions rodam sobre tabelas Delta lidas como DataFrame), ADR-07 (Medalhão — define em quais camadas aplicar)
* Não é dependência de nenhuma outra ADR

### Impacto

Médio — não altera a arquitetura core, mas é diferencial de portfólio e demonstra maturidade operacional.
