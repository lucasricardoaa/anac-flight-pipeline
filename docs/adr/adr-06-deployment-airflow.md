# ADR-06: Deployment do Airflow — VM Compute Engine e2-medium com Docker Compose

## Status

Proposta

> _Esta decisão foi tomada durante a fase de planejamento — nenhuma fase do projeto foi implementada. O status será revisado para `Aceita` após implementação e validação em ambiente real._

---

## Contexto

### A pergunta que esta ADR responde

A ADR-01 decidiu que o orquestrador do pipeline é o Apache Airflow 2.8. Esta ADR documenta uma decisão distinta e complementar: onde e como o Airflow roda. São duas decisões separadas porque "usar Airflow" não determina automaticamente "como deployar o Airflow" — existem pelo menos três formas operacionalmente distintas de colocar um Airflow em produção, com implicações de custo, reprodutibilidade e manutenção radicalmente diferentes.

O espaço de escolha para deployment do Airflow em um projeto com infraestrutura no GCP é:

1. Serviço gerenciado no GCP (Cloud Composer)
2. Instalação direta na VM sem containerização
3. Containerização com Docker Compose em VM própria
4. Plataforma gerenciada especializada em Airflow (Astronomer)

As quatro opções entregam um Airflow funcional. A diferença está em custo, reprodutibilidade e overhead operacional — e o constraint de $300 em créditos GCP formalizado na ADR-00 não é um fator entre outros: é o que elimina duas das quatro opções por definição, antes de qualquer análise técnica.

### O constraint financeiro como filtro primário

O free trial do GCP oferece $300 em créditos. Esse número está documentado na ADR-00 como constraint não-funcional de primeira ordem. Antes de qualquer análise de mérito técnico das alternativas de deployment, é necessário verificar quais opções são viáveis dentro do orçamento disponível.

A resposta para Cloud Composer e Astronomer é direta: não são viáveis. O custo mínimo do Cloud Composer (~$300/mês) equivale ao orçamento total do projeto. O Astronomer não tem free tier adequado para o escopo de um projeto de portfólio. Essas rejeições não são preferências técnicas — são inviabilidades financeiras objetivas.

Após esse filtro, o espaço de escolha real se reduz a: instalação direta na VM ou Docker Compose na VM. A decisão entre essas duas opções é técnica — e tem consequências que vão além da conveniência operacional.

### Reprodutibilidade como critério de avaliação de portfólio

Um projeto de portfólio de Engenharia de Dados é avaliado, entre outros critérios, pela capacidade do avaliador de reproduzir o ambiente. Um projeto que exige estado acumulado na VM para funcionar — dependências instaladas manualmente, configurações que não estão no repositório, versões de pacotes que foram sendo ajustadas ao longo do desenvolvimento sem registro — é um projeto que existe em uma máquina, não um projeto de engenharia documentado.

A distinção entre `docker compose up` e "instala seguindo as instruções do README" não é conveniência: é a diferença entre um ambiente cujo estado completo está definido no repositório e um ambiente cujo estado existe implicitamente no sistema operacional de uma máquina específica. Para um projeto de portfólio, o primeiro demonstra maturidade de engenharia. O segundo demonstra que o pipeline funciona em condições específicas não replicáveis.

---

## Decisão

**O Apache Airflow 2.8 é deployado em uma VM Google Compute Engine e2-medium (2 vCPUs, 4 GB RAM), containerizado via Docker Compose usando a imagem oficial `apache/airflow`. O executor utilizado é o LocalExecutor. O banco de metadados é PostgreSQL, também em container.**

Os serviços definidos no `docker-compose.yml` são:

- `airflow-webserver`: interface web do Airflow, exposta na porta configurada da VM
- `airflow-scheduler`: processo que avalia o estado dos DAGs e dispara execuções
- `postgres`: banco de metadados do Airflow (metadata database), responsável por armazenar estado de DAGs, task instances, conexões e variáveis

Não há container de worker separado. Não há Redis. Não há broker de mensagens. O LocalExecutor executa tasks como subprocessos dentro do container do scheduler — sem overhead de Celery, sem coordenação de mensagens entre processos distribuídos.

O ambiente completo é definido pelo `docker-compose.yml` versionado no repositório. Qualquer pessoa com acesso ao repositório e ao GCP pode recriar o ambiente com `git clone` + `docker compose up`, sem necessidade de executar passos manuais de instalação não documentados.

A VM e2-medium é provisionada pelo Terraform — conforme documentado na ADR-08 — e não pelo operador manualmente. Isso garante que a configuração da VM (tipo de máquina, região, imagem de OS, regras de firewall) também é reproduzível e versionada.

---

## Alternativas consideradas

### Google Cloud Composer

**O que é**: serviço gerenciado do GCP que provisiona e opera um ambiente Airflow sem overhead de infraestrutura. O Cloud Composer gerencia o scheduler, o webserver, os workers, o banco de metadados e os upgrades de versão. Integração nativa com o ecossistema GCP: IAM, GCS, logging centralizado no Cloud Logging, métricas no Cloud Monitoring.

**Por que é tecnicamente atraente**: é o deployment do Airflow com menor atrito operacional disponível no GCP. Sem gerenciamento de VM, sem configuração de Docker Compose, sem manutenção de imagem. A integração com os operadores Dataproc usados neste projeto (`DataprocCreateClusterOperator`, `DataprocSubmitJobOperator`, `DataprocDeleteClusterOperator`) é nativa — os provedores Google já estão instalados por padrão. Para um projeto em produção com equipe de dados e orçamento de infraestrutura, o Cloud Composer seria a escolha defensável no GCP.

**Por que foi rejeitado**: inviabilidade financeira direta. O Cloud Composer no tier mínimo custa aproximadamente $300/mês. Esse valor é equivalente ao orçamento total do projeto em créditos GCP. Usar o Cloud Composer consumiria todos os créditos disponíveis antes de qualquer execução de pipeline — sem deixar margem para Dataproc, GCS, tráfego de rede ou qualquer outro serviço. A rejeição não é técnica: é uma restrição de orçamento sem apelação.

Para documentar o número de forma precisa: a VM e2-medium com Docker Compose custa ~$25–30/mês. O Cloud Composer custa ~$300/mês. A diferença é de uma ordem de grandeza, e o Cloud Composer sozinho esgotaria o free trial.

### Instalação direta na VM sem Docker

**O que é**: instalação do Airflow diretamente no sistema operacional da VM via `pip install apache-airflow`, sem camada de containerização. O Airflow roda como processos do OS — webserver, scheduler e workers são processos Python supervisionados por `systemd` ou equivalente.

**Por que poderia fazer sentido**: zero overhead de Docker. Sem camada adicional de abstração entre o Airflow e o sistema operacional. Debugging potencialmente mais direto — sem necessidade de entrar em containers para inspecionar logs. Para ambientes onde Docker não está disponível ou não é permitido, seria a única alternativa.

**Por que foi rejeitado — motivo 1: conflito de dependências Python**

O Airflow tem um conjunto extenso de requisitos de versão de pacotes Python. A instalação direta na VM coloca o Airflow e todas as suas dependências no mesmo ambiente Python do sistema operacional — o mesmo ambiente onde o `google-cloud-sdk`, as ferramentas de administração da VM e eventualmente outros scripts e utilitários estão instalados. Conflitos de versão de dependências entre o Airflow e qualquer outra ferramenta instalada no sistema operacional são um risco concreto, não teórico. O projeto Apache Airflow documenta explicitamente que a instalação em ambientes compartilhados via `pip` é propensa a conflitos e recomenda o uso de ambientes isolados.

**Por que foi rejeitado — motivo 2: ausência de reprodutibilidade**

Uma instalação direta acumula estado implícito no sistema operacional ao longo do tempo. Pacotes Python instalados por `pip` sem pinning de versão derivam à medida que patches de segurança e dependências são atualizados. Configurações do OS ajustadas manualmente durante o desenvolvimento não são registradas em nenhum artefato versionável. O resultado é um ambiente que funciona na VM específica onde foi construído, mas não pode ser recriado em outra máquina com garantia de comportamento idêntico.

Para um projeto de portfólio, isso significa que o avaliador técnico não consegue replicar o ambiente a partir do repositório. O pipeline funciona — mas apenas na VM onde foi instalado, com o estado acumulado que essa VM tem. Isso invalida um dos critérios centrais de avaliação de maturidade de engenharia: reprodutibilidade a partir de código versionado.

### Astronomer

**O que é**: plataforma gerenciada especializada em Apache Airflow com features enterprise. Observabilidade avançada (Astro UI com histórico visual de runs, métricas de DAGs, alertas configuráveis), deploy de DAGs por push (sem acesso SSH à máquina), RBAC nativo, suporte a múltiplos ambientes (dev, staging, prod) por workspace. Tecnicamente superior ao Docker Compose para ambientes de produção com múltiplos desenvolvedores.

**Por que foi rejeitado**: serviço pago sem free tier adequado para o escopo de um projeto de portfólio. O modelo de preço do Astronomer não é compatível com o constraint de $300 da ADR-00. A rejeição é estritamente financeira — as features enterprise do Astronomer têm valor real em contextos de produção, mas esse contexto não é este projeto.

---

## Por que Docker Compose sobre instalação direta

Após a rejeição das alternativas gerenciadas por custo, a decisão real é entre Docker Compose e instalação direta na VM. Três razões concretas, em ordem de importância para este contexto:

**1. Reprodutibilidade**

O arquivo `docker-compose.yml` define completamente o estado do ambiente Airflow: versão exata da imagem (`apache/airflow:2.8.x`), variáveis de ambiente de configuração (`AIRFLOW__CORE__EXECUTOR`, `AIRFLOW__DATABASE__SQL_ALCHEMY_CONN`, `AIRFLOW__CORE__FERNET_KEY`), volumes mapeados para DAGs e logs, serviços e suas dependências. Qualquer pessoa com acesso ao repositório pode recriar o ambiente exato com `docker compose up` — sem executar passos manuais, sem depender de estado acumulado no OS.

Essa propriedade não é conveniente apenas para colaboração: é o que torna o projeto auditável. Um avaliador externo que clona o repositório e executa `docker compose up` obtém o mesmo Airflow que o autor opera — não uma aproximação que pode ou não se comportar de forma idêntica.

**2. Isolamento de dependências**

O Airflow e suas dependências Python rodam inteiramente dentro do container, isoladas do sistema operacional da VM. Outras ferramentas instaladas na VM — incluindo o Terraform, o `google-cloud-sdk`, utilitários de administração — não interferem com o ambiente Python do Airflow. O container define seu próprio ambiente; o OS da VM não sabe o que está instalado dentro dele.

Esse isolamento elimina a categoria inteira de problemas de conflito de dependências que tornam a instalação direta arriscada. O ambiente do Airflow é determinístico porque está encapsulado.

**3. Manutenção upstream**

A imagem oficial `apache/airflow` é mantida pela comunidade Apache. Patches de segurança, correções de compatibilidade de dependências e novas versões do Airflow são publicados como novas tags da imagem. Atualizar o Airflow é mudar a tag no `docker-compose.yml` e executar `docker compose pull` — sem reinstalar dependências manualmente, sem resolver conflitos de versão no OS. O overhead de manutenção do ambiente é transferido para upstream.

---

## LocalExecutor: por que não CeleryExecutor

O Docker Compose pode ser configurado com diferentes executores. Para este projeto, o LocalExecutor é a escolha adequada.

**O que LocalExecutor faz**: executa tasks como subprocessos no mesmo container do scheduler. O scheduler avalia os DAGs, decide quais tasks devem ser disparadas e as executa como subprocessos dentro do próprio container. Sem broker de mensagens, sem workers separados, sem coordenação distribuída.

**O que CeleryExecutor exigiria**: um broker de mensagens — Redis ou RabbitMQ — para coordenar a distribuição de tasks entre o scheduler e os workers. Dois ou mais containers adicionais no `docker-compose.yml`: o broker e pelo menos um worker. Configuração de conexão entre scheduler, broker e workers. Consumo de memória adicional na VM para cada worker em execução.

**Por que CeleryExecutor não faz sentido aqui**: o overhead do CeleryExecutor é justificado quando há necessidade de paralelismo horizontal real — múltiplos workers em hosts separados executando dezenas ou centenas de tasks simultaneamente. Para um pipeline com execução mensal, um único DAG principal e volume controlado de tasks, esse overhead não tem retorno. O LocalExecutor executa as tasks do pipeline com latência mínima e sem a complexidade operacional adicional de manter um broker de mensagens em estado saudável.

A ausência de CeleryExecutor significa que o Airflow não tem alta disponibilidade de workers. Isso é um trade-off documentado e aceito: um projeto de portfólio de execução mensal não tem SLA de disponibilidade que justifique a complexidade de HA no executor.

---

## Consequências

### Positivas

**Custo dentro do constraint**: ✓ Resolvido: a VM e2-medium em `us-central1` custa ~$0.0336/hora (~$24/mês). A estimativa de planejamento de $25–30/mês estava dentro do intervalo correto. Com o free trial de $300, a VM é sustentável por ~12 meses — compatível com o escopo de desenvolvimento de um projeto de portfólio. Isso contrasta diretamente com o Cloud Composer, que consumiria o orçamento total em menos de um mês.

**Reprodutibilidade como demonstração de maturidade**: um projeto reproduzível com `git clone` + `docker compose up` + `terraform apply` demonstra, sem argumento adicional, que o autor sabe tratar infraestrutura como código. O avaliador técnico não precisa confiar que o ambiente "provavelmente funciona" — ele pode verificar. Essa propriedade é o que separa um projeto de portfólio de um script em produção não documentada.

**Isolamento real de dependências**: o Airflow em container não conflita com o Terraform, o `google-cloud-sdk` ou qualquer outra ferramenta da VM. O ambiente de orquestração é determinístico independente do que mais está instalado na VM.

**Imagem oficial mantida upstream**: atualizações de segurança e novas versões do Airflow chegam via `docker compose pull` sem overhead de manutenção manual do ambiente Python.

**LocalExecutor adequado ao volume**: sem Redis, sem workers adicionais, sem broker de mensagens. O scheduler executa tasks como subprocessos locais — suficiente para o volume de um pipeline de portfólio com execução mensal.

### Negativas

**Ausência de alta disponibilidade**: um único scheduler em um único container em uma única VM. Se o scheduler cair, o Airflow não agenda novas execuções até ser reiniciado. Se a VM ficar indisponível, o Airflow fica offline. Para um pipeline de portfólio de execução mensal sem SLA de disponibilidade, esse trade-off é aceitável e está documentado como decisão deliberada na ADR-00.

**Memória da VM e2-medium como limite prático**: o e2-medium tem 4 GB de RAM. Com webserver, scheduler e PostgreSQL rodando em containers, o consumo típico em idle está entre 1.5 e 2.5 GB. Com tasks ativas executando — especialmente tasks que chamam a API do GCP, fazem download de CSVs ou submetem jobs ao Dataproc — o consumo pode alcançar 3–3.5 GB. O ambiente é estável para o volume de execuções deste projeto; não é adequado para pipelines com dezenas de tasks em paralelo ou DAGs de alta frequência.

**LocalExecutor sem paralelismo horizontal**: tasks são executadas como subprocessos no container do scheduler. Não há workers em hosts separados. O paralelismo é limitado pela capacidade da VM — o que é suficiente para este projeto, mas seria um gargalo em pipelines de produção com volume significativo de tasks simultâneas.

**Falta de observabilidade centralizada**: sem Cloud Composer ou Astronomer, o Airflow não tem integração automática com Cloud Logging ou Cloud Monitoring. Logs ficam no container e precisam ser acessados via `docker logs` ou por volume mapeado no host. Isso é funcional para um projeto de portfólio — mas seria inadequado para um ambiente de produção onde centralização de logs e alertas são requisitos operacionais.

---

## Estimativa de custo e viabilidade dentro do free trial

| Componente | Custo mensal estimado |
|---|---|
| VM e2-medium (Airflow + Docker Compose) | ~$25–30/mês |
| Cloud Composer (alternativa rejeitada) | ~$300/mês |
| Astronomer (alternativa rejeitada) | Pago, sem free tier adequado |

✓ Resolvido: e2-medium em `us-central1` — ~$0.0336/hora (~$24/mês). Estimativa de planejamento confirmada.

Com $300 em créditos GCP e custo de VM de ~$25–30/mês, o orçamento para a VM do Airflow ao longo de 10 meses é de ~$250–300. Na prática, o projeto também consome créditos com GCS, Dataproc e tráfego de rede — conforme estimativa detalhada na ADR-03 para o componente Dataproc. O custo do Dataproc ao longo do projeto foi estimado em $4–6 para ~100 execuções de desenvolvimento + 12 mensais, o que deixa a maior parte do orçamento para a VM do Airflow e outros serviços GCP.

A escolha por Docker Compose na e2-medium é, portanto, não apenas tecnicamente justificável mas financeiramente necessária: é a única opção que entrega um Airflow funcional dentro do constraint de $300.

---

## Dependências

### Esta ADR depende de

| ADR | Dependência |
|---|---|
| ADR-00 | O constraint de $300 em créditos GCP elimina Cloud Composer (~$300/mês) e Astronomer (pago sem free tier) por inviabilidade financeira direta. Sem o contexto formalizado na ADR-00, as rejeições dessas alternativas pareceriam preferências técnicas — são restrições de orçamento. |
| ADR-01 | Esta ADR define onde e como o Airflow roda, pressupondo que a escolha do Airflow como orquestrador já foi tomada. A decisão de usar Airflow sobre Prefect, Dagster e cron está na ADR-01. A ADR-06 não redefine essa escolha — a consome como premissa. |

### Esta ADR é dependência de

| ADR | Dependência |
|---|---|
| ADR-08 | O Terraform documentado na ADR-08 provisiona a VM e2-medium onde o Airflow roda — tipo de máquina, região, imagem de OS, regras de firewall para acesso à interface web. As especificações da VM que o Terraform precisa implementar decorrem das decisões documentadas aqui. |

---

## Referências

- ADR-00: Contexto Global e Constraints do Projeto
- ADR-01: Orquestrador de Pipelines — Apache Airflow 2.8 com TaskFlow API
- ADR-08: Provisionamento de Infraestrutura com Terraform (a ser criada)
- [Apache Airflow — Running Airflow in Docker](https://airflow.apache.org/docs/apache-airflow/stable/howto/docker-compose/index.html)
- [Apache Airflow — Executors](https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/executor/index.html)
- [Apache Airflow — LocalExecutor](https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/executor/local.html)
- [Docker Hub — apache/airflow](https://hub.docker.com/r/apache/airflow)
- [Google Cloud — Compute Engine VM instance pricing](https://cloud.google.com/compute/vm-instance-pricing)
- [Google Cloud Composer — Overview](https://cloud.google.com/composer/docs/concepts/overview)
- [Google Cloud Composer — Pricing](https://cloud.google.com/composer/pricing)
