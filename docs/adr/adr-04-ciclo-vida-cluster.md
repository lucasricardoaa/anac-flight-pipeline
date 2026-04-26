# ADR-04: Ciclo de Vida do Cluster Dataproc — Efêmero com Defesa em Profundidade contra Cluster Órfão

## Status

Proposta

> _Esta decisão foi tomada durante a fase de planejamento — nenhuma fase do projeto foi implementada. O status será revisado para `Aceita` após implementação e validação em ambiente real._

---

## Contexto

### O cluster Dataproc não é infraestrutura permanente

A ADR-03 decidiu que o PySpark é executado em cluster Google Cloud Dataproc gerenciado no GCP. Essa decisão levanta uma pergunta operacional imediata: o cluster deve existir continuamente, ou apenas durante a execução de cada run do pipeline?

A resposta determina:

- O custo mensal de infraestrutura do projeto
- O que acontece quando um job Spark falha no meio de uma execução
- O que acontece quando o Airflow scheduler cai enquanto o cluster está ativo

Essas três perguntas têm respostas interdependentes, e a decisão sobre o ciclo de vida do cluster precisa tratar as três de forma integrada.

### O constraint financeiro elimina cluster permanente

O free trial do GCP oferece $300 em créditos — constraint formalizado na ADR-00 como determinante de várias decisões de infraestrutura. Um cluster e2-standard-2 com 1 master + 2 workers custa aproximadamente $0.10/hora de cluster ativo. Rodando continuamente, sem executar nenhum job:

- Por dia: ~$2.40
- Por mês: ~$72–200 (dependendo do tipo exato de máquina e região)

Esse custo sozinho inviabilizaria o projeto dentro do orçamento disponível, ainda antes de contabilizar VM do Airflow, storage no GCS, tráfego de rede e outros serviços.

### O risco de cluster órfão é real e tem custo mensurável

Um cluster que fica ativo além do necessário — porque o Airflow não executou a task de destruição, porque o scheduler caiu, porque houve perda de conectividade entre a VM e a API do GCP — é um cluster órfão. Ele não faz nenhum trabalho útil, mas é cobrado normalmente enquanto estiver ativo.

Com a configuração de referência deste projeto (~$0.10/hora), um cluster órfão que roda por uma noite inteira (8 horas) representa $0.80 de custo. Por uma semana, $8–12. Em um free trial de $300, algumas ocorrências desse tipo não são apenas inconvenientes — elas comprometem a viabilidade do projeto.

A causa mais comum de cluster órfão não é descuido: é falha de infraestrutura de orquestração. Job Spark que falha e interrompe o DAG antes da task de destruição. Scheduler do Airflow que reinicia enquanto o cluster está ativo. VM do Airflow que perde conectividade com a API do GCP. Esses cenários são raros, mas possíveis — e a estratégia de ciclo de vida do cluster precisa cobri-los.

### A dataset da ANAC não tem requisito de latência baixa

As estatísticas de transporte aéreo doméstico da ANAC são publicadas mensalmente. O pipeline executa uma vez por mês para processar o mês anterior. Não há SLA de latência, não há processamento em tempo real, não há dependência downstream que exija resultado em minutos após o disparo.

Esse contexto é relevante porque a alternativa de cluster efêmero introduz um overhead de 3–5 minutos de provisionamento no início de cada execução. Em um pipeline com requisito de latência, esse overhead seria um critério de rejeição. Neste projeto, é completamente aceitável: uma execução mensal com 5 minutos de cold start adicional não representa impacto operacional relevante.

---

## Decisão

**O cluster Dataproc não existe entre execuções. Cada run do DAG cria o cluster, submete os jobs Spark e destrói o cluster ao final — independente de sucesso ou falha dos jobs.**

A proteção contra cluster órfão usa duas camadas independentes:

**Camada 1 — Airflow (`trigger_rule='all_done'` + `execution_timeout`):**

A task `DataprocDeleteClusterOperator` é configurada com `trigger_rule='all_done'`. Por padrão, o Airflow usa `trigger_rule='all_success'`: uma task só é executada se todas as tasks upstream completaram com sucesso. Com `trigger_rule='all_done'`, a task de destruição do cluster executa quando todas as tasks upstream terminaram — independente de terem falhado, sido ignoradas ou completado com sucesso.

Sem essa configuração, um job Spark que falha interrompe o DAG antes de chegar na task de destruição, deixando o cluster ativo indefinidamente. Com `trigger_rule='all_done'`, a falha de qualquer job Spark não impede a destruição do cluster — a task de delete executa de qualquer forma.

A task de delete é complementada com `execution_timeout` configurado. Se a chamada à API do GCP para destruição do cluster travar — por lentidão na API, por timeout de rede — o Airflow não fica aguardando indefinidamente. O timeout força a falha da task, o DAG é marcado como falho e o scheduler avança. O cluster ainda pode permanecer ativo nesse cenário específico, mas o DAG não fica preso em estado indefinido.

**Camada 2 — Dataproc (`lifecycle_config.auto_delete_ttl`):**

O cluster é criado com `max_age` configurado no campo `lifecycle_config.auto_delete_ttl`. O Dataproc destrói o cluster automaticamente após o TTL expirar, independente do estado do Airflow ou da VM onde ele roda. Essa destruição acontece no nível da API do GCP — não requer que o Airflow scheduler esteja ativo, não requer conectividade entre a VM e o Dataproc, não requer nenhuma ação do orquestrador.

O TTL é dimensionado em 2× o tempo esperado de execução completa do pipeline. Se uma execução normal leva ~30 minutos (provisionamento + jobs Bronze/Silver/Gold + destruição), o TTL é configurado para 60–90 minutos. Esse multiplicador garante que execuções legítimas com alguma lentidão pontual — job Spark mais lento em um dataset maior, latência de API, retry de task — não sejam interrompidas prematuramente pelo próprio mecanismo de proteção. `[VERIFICAR]` — o tempo exato de execução do pipeline completo precisa ser medido após as primeiras execuções de validação, e o TTL ajustado conforme necessário.

A combinação das duas camadas é defesa em profundidade: a Camada 1 cobre o caso normal de falha de job ou task; a Camada 2 cobre os cenários em que a própria infraestrutura de orquestração falha. Cada camada é independente — a falha de uma não compromete a outra.

---

## Alternativas consideradas

### Cluster permanente

**O que é**: cluster Dataproc provisionado uma única vez e mantido rodando continuamente. Jobs Spark são submetidos ao cluster existente sem overhead de provisionamento — o cluster está sempre disponível, workers já registrados no YARN, latência de execução determinada apenas pelo job.

**Vantagens técnicas reais**: elimina o cold start de 3–5 minutos por execução. Simplifica a operação do DAG — sem task de criação, sem task de destruição, sem necessidade de configurar `trigger_rule` para garantir destruição após falha. O DAG se torna uma sequência de submissões de job Spark a um endpoint estável.

**Por que foi rejeitado**: custo proibitivo dentro do constraint de $300 documentado na ADR-00. A configuração de referência (1 master e2-standard-2 + 2 workers e2-standard-2) a ~$0.10/hora consumiria ~$72/mês apenas para o cluster parado, sem executar nenhum job. Em dois meses, o orçamento total do projeto estaria comprometido apenas com o cluster, antes de qualquer execução de pipeline. A rejeição não é técnica — é estritamente financeira.

### Cluster compartilhado entre DAGs

**O que é**: um cluster Dataproc de vida longa, não permanente, compartilhado entre múltiplos DAGs que executam em sobreposição. O cluster é criado quando o primeiro DAG começa e destruído quando o último DAG termina, com lógica de coordenação para evitar destruição prematura.

**Vantagens técnicas reais**: reduz o custo de provisionamento quando múltiplos DAGs executam em janelas temporais sobrepostas. Um único cold start de 3–5 minutos serve múltiplas execuções simultâneas.

**Por que foi rejeitado**: complexidade de gerenciamento injustificada para este projeto. Compartilhamento de cluster entre DAGs requer coordenação de concorrência — dois DAGs não podem destruir o cluster simultaneamente, o cluster não pode ser destruído enquanto um job de outro DAG ainda está rodando. Isso implica mecanismo de lock distribuído ou contador de referências de uso, lógica de decisão sobre quando destruir, e tratamento de cenários de race condition. Para um projeto com um único DAG principal e execução mensal não-sobreposta, a complexidade de gerenciamento pesa mais do que o benefício de redução de cold start. Rejeitado por princípio de simplicidade operacional.

### Dataproc Serverless

**O que é**: modalidade do Dataproc sem gestão de cluster. O job PySpark é submetido diretamente à API do Dataproc Serverless, que aloca recursos automaticamente, executa o job e libera os recursos ao final. Não há cluster para criar ou destruir.

**Vantagens técnicas reais**: elimina o problema de ciclo de vida de cluster por completo. Sem `DataprocCreateClusterOperator`, sem `DataprocDeleteClusterOperator`, sem risco de cluster órfão. O custo é proporcional à computação efetivamente utilizada.

**Por que foi rejeitado**: pelos mesmos motivos documentados na ADR-03 — custo menos previsível durante desenvolvimento (muitas execuções de teste com variabilidade de custo por DCU-hora), menor valor didático como demonstração de Spark distribuído com cluster gerenciado, e menor presença em materiais de estudo e JDs de vagas Pleno no Brasil. A ADR-04 herda essa rejeição da ADR-03 sem necessidade de argumentação adicional.

---

## Consequências

### Positivas

**Custo por execução controlado e previsível**: com cluster efêmero e configuração fixa (e2-standard-2 × 3 nós), o custo por execução é determinístico. Aproximadamente 20 minutos de cluster ativo por execução normal = $0.03–0.05 por run. Projetando 100 execuções de desenvolvimento + 12 execuções mensais de operação = $4–6 de custo total de Dataproc ao longo do projeto — menos de 2% do orçamento de $300.

**Proteção financeira contra falhas com custo máximo determinístico**: com as duas camadas de proteção ativas, o pior cenário possível tem custo conhecido. Se o Airflow falhar completamente e o cluster não for destruído pela Camada 1, o Dataproc destrói automaticamente pelo TTL configurado. Para TTL de 90 minutos: custo máximo de ~$0.15 por ocorrência, independente de quantas horas o Airflow fique inativo depois. Sem proteção alguma, o mesmo cenário poderia resultar em $8–12 de custo por semana de cluster ativo.

**Demonstração de raciocínio de engenharia além do caminho feliz**: a combinação de `trigger_rule='all_done'` + `lifecycle_config.auto_delete_ttl` é um padrão de defesa em profundidade — múltiplas camadas independentes cobrindo cenários de falha distintos. Para um portfólio que precisa convencer engenheiros seniores de que o autor pensa além da execução normal, essa escolha de design fala por si. Engenheiros avaliadores vão perguntar "o que acontece se o job Spark falhar?" — a resposta está documentada e implementada.

**`trigger_rule='all_done'` como demonstração técnica precisa**: esse conceito aparece com frequência em entrevistas técnicas para vagas Pleno como critério de diferenciação entre candidatos que entendem o modelo de execução do Airflow e candidatos que apenas escrevem DAGs para o caminho feliz. Implementá-lo corretamente e documentar o raciocínio por trás da escolha reforça o valor didático do portfólio.

### Negativas

**Cold start de 3–5 minutos por execução**: cada execução aguarda o provisionamento completo do cluster Dataproc. Esse overhead é aceito porque o requisito de frequência é mensal e não há SLA de latência. Em qualquer pipeline com requisito de latência — processamento near-real-time, SLA de minutos — essa abordagem seria inadequada. O contexto que torna esse trade-off aceitável está documentado na ADR-00 e na seção de Contexto acima.

**Custo de provisionamento como parcela do tempo total de execução**: em uma execução de ~20 minutos, 3–5 minutos (15–25% do tempo) são consumidos pelo provisionamento do cluster, não pelo processamento de dados. Isso é uma ineficiência real — em produção, seria endereçada com pool de clusters pré-aquecidos ou Dataproc Serverless. Para este projeto, a proporção é aceitável.

**TTL requer calibração após primeiras execuções**: o TTL configurado no `lifecycle_config.auto_delete_ttl` é uma estimativa no momento da escrita desta ADR. Execuções com datasets maiores ou retries de tasks podem exceder o tempo esperado. Se o TTL for muito curto, o Dataproc destrói o cluster durante uma execução legítima, causando falha do pipeline por motivo diferente do esperado. O valor precisa ser revisado após as primeiras execuções de validação. Ver nota `[VERIFICAR]` na seção de Decisão.

**`execution_timeout` na task de delete não garante destruição**: se a task de destruição do cluster falhar por timeout de conectividade com a API do GCP, o cluster pode permanecer ativo até o TTL da Camada 2 expirar. A Camada 1 com `execution_timeout` garante que o DAG avança — não garante que o cluster foi destruído. A garantia de destruição em cenários extremos é responsabilidade exclusiva da Camada 2. Esse comportamento é intencional e documentado.

---

## Estimativa de custo por cenário

Configuração de referência: 1 master e2-standard-2 + 2 workers e2-standard-2, ~$0.10/hora de cluster ativo. A escolha do tipo de máquina e2-standard-2 é definida na ADR-03 — qualquer restrição de disponibilidade desse tipo em Dataproc (por região ou por imagem de cluster) é tratada naquela ADR e se aplica diretamente aqui. `[VERIFICAR]` — confirmar preços atuais para a região de deployment em [https://cloud.google.com/compute/vm-instance-pricing](https://cloud.google.com/compute/vm-instance-pricing).

| Cenário | Tempo de cluster ativo | Custo estimado |
|---|---|---|
| Execução normal (provisionamento + jobs + destruição) | ~20 minutos | $0.03–0.05 |
| Falha de job Spark com Camada 1 ativa (`trigger_rule='all_done'`) | ~15 minutos (até destruição imediata após falha) | ~$0.03 |
| Falha do Airflow com Camada 2 ativa (TTL de 90 minutos) | TTL restante no momento da falha, máximo 90 minutos | máximo ~$0.15 |
| Cluster órfão sem proteção alguma — noite inteira | 8–10 horas | $0.80–1.00 |
| Cluster órfão sem proteção alguma — uma semana | ~168 horas | $8–12 |

A diferença entre "sem proteção" e "com Camada 2 ativa" no pior cenário é de $0.80–12.00 versus $0.15 por ocorrência. O overhead de implementação das duas camadas — que é praticamente zero em complexidade de código — tem retorno direto e mensurável.

---

## Dependências

### Esta ADR depende de

| ADR | Dependência |
|---|---|
| ADR-00 | O constraint de $300 em créditos GCP é o argumento central que torna cluster permanente inviável. Sem o contexto formalizado na ADR-00, a rejeição de cluster permanente pareceria uma decisão técnica subótima — é uma decisão financeira deliberada. |
| ADR-03 | Esta ADR define *como* gerenciar o ciclo de vida do cluster Dataproc cuja escolha foi feita na ADR-03. Sem a ADR-03 ter selecionado Dataproc gerenciado como ambiente de execução do PySpark, a ADR-04 não teria objeto. |

### Esta ADR é dependência de

| ADR | Dependência |
|---|---|
| ADR-08 | O Terraform que provisiona o cluster Dataproc precisa incluir `lifecycle_config.auto_delete_ttl` com o TTL correto no recurso `google_dataproc_cluster`. Sem essa configuração no IaC, a Camada 2 de proteção não existe — o cluster seria criado sem TTL e dependeria exclusivamente do Airflow para destruição. A ADR-08 precisa implementar essa especificação. |

---

## Referências

- ADR-00: Contexto Global e Constraints do Projeto
- ADR-01: Orquestrador de Pipelines — Apache Airflow 2.8 (define `trigger_rule='all_done'` como mecanismo de proteção na task de destruição do cluster)
- ADR-03: Ambiente de Execução do PySpark — Google Cloud Dataproc (decide o uso de Dataproc gerenciado; esta ADR define o ciclo de vida do cluster resultante)
- ADR-08: Provisionamento de Infraestrutura com Terraform (implementa `lifecycle_config.auto_delete_ttl` no recurso Dataproc)
- [Apache Airflow — Trigger Rules](https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/dags.html#trigger-rules)
- [Apache Airflow — DataprocDeleteClusterOperator](https://airflow.apache.org/docs/apache-airflow-providers-google/stable/operators/cloud/dataproc.html)
- [Google Cloud Dataproc — Cluster lifecycle](https://cloud.google.com/dataproc/docs/concepts/configuring-clusters/scheduled-deletion)
- [Google Cloud Dataproc — `LifecycleConfig.auto_delete_ttl`](https://cloud.google.com/dataproc/docs/reference/rest/v1/projects.regions.clusters#LifecycleConfig)
- [Google Cloud — VM instance pricing (e2-standard-2)](https://cloud.google.com/compute/vm-instance-pricing)
