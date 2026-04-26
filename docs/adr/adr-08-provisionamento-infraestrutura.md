# ADR-08: Provisionamento de Infraestrutura — Terraform como Única Fonte de Verdade para Recursos GCP

## Status

Proposta

> _Esta decisão foi tomada durante a fase de planejamento — nenhuma fase do projeto foi implementada. O status será revisado para `Aceita` após implementação e validação em ambiente real._

---

## Contexto

### A infraestrutura do projeto não se documenta sozinha

O pipeline de dados da ANAC requer uma coleção de recursos GCP interdependentes: uma VM Compute Engine onde o Airflow roda (ADR-06), buckets GCS para as camadas Bronze, Silver e Gold da arquitetura Medalhão (ADR-07), service accounts com permissões IAM específicas para o Dataproc e para o Airflow, configurações de rede que permitem acesso SSH à VM e comunicação interna entre a VM e o Dataproc (ADR-03). Cada um desses recursos tem configuração não trivial — tipos de máquina, regiões, políticas de IAM, regras de firewall, lifecycle rules de bucket.

A questão desta ADR não é quais recursos existem — isso está documentado nas ADRs de cada componente. A questão é como esses recursos são provisionados e gerenciados ao longo do ciclo de vida do projeto.

### Por que a forma de provisionar importa

Há três formas operacionalmente distintas de criar infraestrutura GCP: via console web do GCP, via scripts shell com `gcloud` CLI, ou via ferramenta de Infrastructure as Code (IaC). As três entregam os mesmos recursos. A diferença está no que acontece depois da criação — quando algo muda, quando o ambiente precisa ser recriado, quando alguém precisa auditar o que existe.

Para um projeto de portfólio com objetivo de demonstrar maturidade de engenharia de plataforma (documentado na ADR-00), essa diferença não é um detalhe operacional: é o argumento central. Um projeto onde `git clone` + `terraform apply` + `docker compose up` recria toda a infraestrutura de forma determinística faz uma afirmação que provisionamento manual nunca pode fazer — que o estado do ambiente está completamente descrito em código versionado.

### Relação com o objetivo de portfólio

O contexto global do projeto está documentado na ADR-00. O motivador primário é aprendizado de PySpark e Airflow para posicionamento em vagas de Engenheiro de Dados Pleno no mercado brasileiro. O Terraform é citado com frequência crescente em job descriptions para vagas Pleno e SRE no Brasil — não como requisito absoluto, mas como diferencial que separa candidatos com experiência de infraestrutura como código daqueles que dependem de provisionamento manual ou de operações de DevOps para configurar ambientes. Para um portfólio, documentar IaC com racional técnico preciso agrega mais valor do que mencioná-lo de passagem no README.

---

## Decisão

**Toda a infraestrutura GCP do projeto é declarada, versionada e gerenciada via Terraform.**

Os recursos GCP não existem como configuração manual no console, não são criados por scripts shell, e não dependem de estado implícito em ambiente local. Eles existem como código HCL versionado no repositório — aplicados via `terraform apply`, inspecionados via `terraform plan` antes de qualquer mudança, formatados via `terraform fmt` e validados via `terraform validate` como parte do ciclo de desenvolvimento.

A infraestrutura deixa de ser um conjunto de recursos que o autor sabe que existem. Torna-se um conjunto de recursos que qualquer pessoa com acesso ao repositório e credenciais GCP pode recriar de forma determinística.

---

## Alternativas consideradas

### Scripts shell com gcloud CLI

**O que é**: provisionamento imperativo via `gcloud` CLI em scripts shell. Cada script descreve a sequência de comandos para criar os recursos necessários — `gcloud compute instances create`, `gcloud storage buckets create`, `gcloud iam service-accounts create` e derivados. Baixa barreira de entrada: o `gcloud` CLI já está disponível no ambiente de desenvolvimento, sem necessidade de instalar ou aprender uma ferramenta adicional.

**Por que foi rejeitado**: quatro problemas estruturais, nenhum contornável dentro da abordagem imperativa.

Primeiro, **ausência de state management**. Um script shell não sabe o que já existe. Cada execução descreve os comandos a executar — não o estado que a infraestrutura deve ter. Se um bucket já existe e o script tenta criá-lo novamente, o resultado é um erro ou um comportamento inesperado, dependendo das flags usadas. Não há equivalente ao `terraform.tfstate` — nenhum registro canônico de quais recursos foram criados, com quais configurações, em qual estado atual.

Segundo, **sem detecção de drift**. Se um recurso é modificado manualmente no console GCP depois de ter sido criado pelo script, o script não tem como saber. O script descreve a criação, não o estado desejado. A divergência entre o que o script define e o que realmente existe no GCP — drift — é invisível. Com Terraform, `terraform plan` expõe o drift imediatamente: mostra a diferença entre o estado registrado e o estado real, antes de qualquer mudança.

Terceiro, **sem idempotência garantida**. Executar o mesmo script duas vezes pode criar recursos duplicados, falhar com erro em recursos já existentes, ou — pior — sobrescrever configurações parcialmente. A idempotência precisa ser implementada manualmente em cada comando, com verificações explícitas de existência antes de cada criação. Isso transforma scripts de provisionamento em lógica de gerenciamento de estado ad hoc — exatamente o problema que o Terraform resolve de forma estruturada.

Quarto, e critério eliminatório para este projeto: **ausência de plano de execução antes de aplicar**. O Terraform separa `terraform plan` de `terraform apply`. O plan mostra exatamente o que será criado, modificado ou destruído — antes de qualquer mudança ocorrer. Não existe equivalente em scripts shell. A primeira indicação de que um comando vai fazer algo inesperado é quando o comando executa. Em um projeto de portfólio, a capacidade de mostrar `terraform plan` como etapa obrigatória antes de qualquer mudança de infraestrutura é um diferencial de engenharia que scripts shell simplesmente não oferecem.

### Pulumi

**O que é**: IaC com linguagens de programação reais — Python, TypeScript, Go, entre outras. Em vez de HCL, os recursos de infraestrutura são declarados em código Python ou TypeScript usando o SDK do Pulumi. A vantagem central é eliminar a curva de aprendizado de uma linguagem específica (HCL) e permitir o uso de abstrações de programação completas: loops, condicionais, funções de ordem superior, testes unitários da lógica de infraestrutura com frameworks de teste convencionais.

**Por que foi rejeitado**: dois motivos, em ordem de peso.

Primeiro, **menor adoção no mercado de dados brasileiro**. Terraform aparece com frequência significativamente maior em job descriptions para Engenheiro de Dados e SRE no Brasil do que o Pulumi. Para um projeto cujo objetivo declarado na ADR-00 inclui demonstrar tecnologias com presença real no mercado de vagas Pleno brasileiro, essa assimetria de adoção é relevante. A maioria dos projetos de infraestrutura com que um Engenheiro de Dados Pleno vai interagir no mercado brasileiro usa Terraform, não Pulumi.

Segundo, **curva de aprendizado adicional fora do escopo central**. O foco do portfólio é pipeline de dados — PySpark, Airflow, arquitetura Medalhão, Delta Lake. Adicionar Pulumi introduz uma curva de aprendizado de SDK de IaC programático que não contribui diretamente para o objetivo de aprendizado do projeto. O HCL do Terraform é deliberadamente simples — declarativo, sem lógica de controle complexa — o que é adequado para o escopo de recursos que este projeto precisa gerenciar. O Pulumi seria a escolha superior em um projeto focado em engenharia de plataforma com infraestrutura complexa e altamente parametrizada. Aqui é overhead sem retorno proporcional.

### Provisionamento manual via console GCP

**O que é**: criação e configuração de recursos GCP via interface gráfica web. Zero curva de aprendizado de ferramenta, feedback visual imediato, nenhuma instalação adicional.

**Por que foi rejeitado**: três razões sem mitigação possível, nenhuma contornável.

Primeiro, **não é reproduzível**. Recriar o ambiente em outra conta GCP — ou na mesma conta após uma destruição acidental — requer memória ou documentação manual de cada configuração. Não há artefato que descreva o estado do ambiente: ele existe apenas no console GCP. Para um projeto de portfólio que precisa demonstrar que o ambiente pode ser recriado a partir do repositório, isso é uma falha estrutural, não um trade-off.

Segundo, **não é versionável**. Mudanças de configuração feitas no console não geram histórico, não têm diff, não têm rollback. Não há como saber o que foi alterado entre dois momentos no tempo, por quem, com qual intenção. A infraestrutura existe como estado opaco no GCP, não como código auditável.

Terceiro, **não demonstra maturidade de engenharia**. Um projeto de portfólio Pleno onde a infraestrutura existe apenas como configuração no console não convence engenheiros seniores de que o autor entende ciclo de vida de infraestrutura real. A pergunta "como você recriaria esse ambiente do zero?" não tem resposta satisfatória quando a resposta é "clicando nas mesmas opções no console".

---

## Recursos gerenciados pelo Terraform neste projeto

### VM Compute Engine (e2-medium) — ambiente do Airflow

O Terraform declara a VM onde o Airflow roda com Docker Compose, conforme definido na ADR-06. O recurso inclui: tipo de máquina (`e2-medium`), imagem de sistema operacional, configuração de disco, região e zona de deployment, service account associada à VM, e regras de firewall para acesso SSH e à porta da interface web do Airflow.

O startup script de instalação do Docker na VM pode ser parametrizado como `metadata_startup_script` no recurso `google_compute_instance` ou gerenciado como etapa separada de configuração de SO. `[VERIFICAR]` — definir durante a implementação se o script de bootstrap do Docker é parte do recurso Terraform ou etapa de configuração documentada no README.

### GCS buckets — camadas da arquitetura Medalhão e state do Terraform

O Terraform declara os buckets das camadas Bronze, Silver e Gold da arquitetura Medalhão (ADR-07), com configuração de classe de armazenamento e lifecycle rules para expiração de objetos temporários onde aplicável.

`[VERIFICAR]` — definir durante a implementação quais buckets têm lifecycle rules configuradas e qual política de expiração é adequada para cada camada. A camada Bronze, como fonte de verdade imutável (ADR-07), não deve ter lifecycle rules de expiração sobre os dados ingeridos. Objetos temporários de jobs Spark podem ser candidatos a expiração.

Se remote state em GCS for adotado (ver seção de backend abaixo), o bucket de state também é declarado pelo Terraform — com a ressalva do problema de bootstrap documentada adiante.

### Dataproc — configuração base e permissões IAM

O Terraform gerencia o contexto de infraestrutura no qual o cluster Dataproc efêmero opera: configuração da imagem de cluster compatível com a versão de `delta-spark` adotada (ADR-03), configurações de rede para que o cluster possa acessar os buckets GCS das camadas Medalhão, e as permissões IAM necessárias para a service account do Dataproc.

O que o Terraform **não** gerencia é o cluster de execução em si. O cluster efêmero — criado antes de cada run do pipeline e destruído ao final, com `lifecycle_config.auto_delete_ttl` configurado como proteção contra cluster órfão — é responsabilidade do Airflow via `DataprocCreateClusterOperator` e `DataprocDeleteClusterOperator`. Esse ciclo de vida está documentado na ADR-04. A ADR-08 provisiona o ambiente; a ADR-04 gerencia o objeto efêmero que opera nesse ambiente.

A fronteira é clara: o Terraform define o que persiste entre execuções do pipeline. O Airflow gerencia o que existe apenas durante cada execução.

### IAM — service accounts, roles e bindings

O Terraform declara as service accounts do projeto — uma para o Airflow (com permissões para criar e destruir clusters Dataproc, acessar buckets GCS e submeter jobs) e uma para o Dataproc (com permissões para ler e escrever nos buckets GCS das camadas Medalhão).

O princípio de menor privilégio é aplicado: cada service account recebe apenas as permissões necessárias para seu papel no pipeline. Os recursos Terraform relevantes incluem `google_service_account`, `google_project_iam_binding` e `google_service_account_iam_member`, conforme o escopo de cada binding.

`[VERIFICAR]` — mapear durante a implementação o conjunto exato de roles necessárias para cada service account, com base nas operações que cada componente executa. Roles excessivamente permissivas (`roles/owner`, `roles/editor`) não são adequadas para service accounts de componentes com escopos funcionais delimitados.

### VPC e configurações de rede

O Terraform declara as regras de firewall necessárias para acesso SSH à VM do Airflow e para tráfego entre a VM e o Dataproc.

**Decisão**: o projeto usa a VPC default do GCP com firewall rules explícitas declaradas no Terraform. Uma VPC dedicada foi avaliada e rejeitada por adicionar complexidade de configuração de rede — declaração de rede, sub-redes, roteamento — sem benefício funcional para o escopo do projeto. A VPC default do GCP já fornece o isolamento necessário para um projeto single-account de portfólio; o que o Terraform gerencia são as regras de firewall que controlam quais portas e origens têm acesso permitido à VM e ao tráfego interno entre VM e Dataproc.

---

## Estratégia de backend para o Terraform state

O state do Terraform é o registro canônico de quais recursos existem e qual é a configuração atual de cada um. É o que permite ao Terraform detectar drift, calcular o plano de mudanças e garantir idempotência entre execuções de `terraform apply`. A escolha do backend determina onde esse state é armazenado.

### Local state

O state é salvo em `terraform.tfstate` no sistema de arquivos local. Funciona imediatamente, sem configuração adicional, sem dependência externa. Para um projeto solo sem execução paralela de `terraform apply` — o que é o caso deste projeto — o risco de corrupção por operações concorrentes é praticamente nulo.

Desvantagens concretas: o arquivo de state não é compartilhável sem mecanismo adicional (como commit no repositório, que é desencorajado porque `terraform.tfstate` pode conter valores sensíveis). Não tem locking nativo. Se o ambiente local for comprometido ou o arquivo perdido, o Terraform perde a rastreabilidade dos recursos existentes — o que não os destrói, mas impede que o Terraform os gerencie corretamente sem importação manual (`terraform import`).

Para um projeto solo de portfólio, local state é uma escolha defensável se documentada conscientemente e se o arquivo de state for tratado com cuidado (nunca commitado no repositório, incluído no `.gitignore`).

### Remote state em GCS bucket

O state é salvo em um bucket GCS, com locking nativo via Cloud Storage object versioning. Compartilhável, auditável, mais próximo do padrão de produção. Integra melhor com GitHub Actions — um workflow que executa `terraform plan` ou `terraform apply` em CI/CD pode acessar o state remoto sem depender do estado do ambiente local do desenvolvedor.

O problema do bootstrap: o bucket de state precisa existir antes do primeiro `terraform apply` que gerencia os demais recursos. Mas se o bucket de state é ele próprio um recurso GCP, quem cria o bucket de state? Esse problema — coloquialmente chamado de "problema do ovo e da galinha" em IaC — tem duas soluções práticas:

**Opção A**: criar o bucket de state manualmente com `gcloud storage buckets create` antes do primeiro `terraform apply`. É um desvio pontual do princípio de tudo-como-código, aceito como exceção de bootstrap e documentado no README do projeto. O restante da infraestrutura permanece gerenciado pelo Terraform.

**Opção B**: manter um conjunto mínimo de Terraform separado (frequentemente chamado de `bootstrap` ou `init`) dedicado exclusivamente à criação do bucket de state, com backend local. O bucket criado por esse Terraform mínimo passa a ser o backend remoto do Terraform principal. A desvantagem é a complexidade de dois conjuntos de Terraform com backends distintos.

**Decisão**: remote state em bucket GCS, com bootstrap via Opção A. O bucket de state é criado manualmente com `gcloud storage buckets create` uma única vez, antes do primeiro `terraform apply`. Esse passo é aceito como exceção de bootstrap documentada — um desvio pontual e justificado do princípio de tudo-como-código, não uma inconsistência. Todo o restante da infraestrutura permanece gerenciado pelo Terraform. A Opção B — Terraform-dentro-de-Terraform com dois backends distintos — foi rejeitada por introduzir complexidade de manutenção (dois state files, dois diretórios de configuração, dois ciclos de `init` + `apply`) sem benefício proporcional para um projeto de portfólio. O passo de criação do bucket de state deve estar documentado no README do projeto como pré-requisito obrigatório antes do primeiro `terraform apply`.

---

## Integração com CI/CD via GitHub Actions

O Terraform se integra ao fluxo de desenvolvimento via GitHub Actions em escopos progressivos de automação. A escolha do escopo determina quanta validação automática acontece antes que mudanças de infraestrutura sejam aplicadas.

### Escopo mínimo — `terraform fmt --check` e `terraform validate` no PR

`terraform fmt --check` falha o workflow se o código HCL não estiver formatado conforme o padrão canônico do Terraform. `terraform validate` falha o workflow se houver erros de sintaxe ou referências inválidas no código HCL. Juntos, garantem que o repositório nunca aceita código Terraform com formatação incorreta ou erros básicos de sintaxe.

Custo de implementação: mínimo — dois comandos em um step de GitHub Actions, sem necessidade de credenciais GCP para execução. Valor: baseline de qualidade que impede degradação do código Terraform ao longo do projeto.

### Escopo intermediário — `terraform plan` no PR

Executa o plano completo de mudanças e exibe o output como comentário no PR antes do merge. O avaliador vê exatamente quais recursos seriam criados, modificados ou destruídos antes de aprovar a mudança.

Requer credenciais GCP configuradas no GitHub Secrets. **Decisão**: a autenticação usa chave JSON de service account armazenada como GitHub Secret (`GOOGLE_CREDENTIALS`), consumida pelo workflow via `google-github-actions/auth`. O Workload Identity Federation — que autentica o GitHub Actions no GCP via tokens de curta duração, sem chave JSON persistida em secret — foi avaliado e rejeitado: exige configuração de pool de identidades, provider OIDC e binding entre o provider e a service account no GCP, uma superfície de configuração que não agrega valor proporcional para um projeto de portfólio de Engenharia de Dados. A chave JSON em GitHub Secret é o mecanismo padrão adotado pela comunidade para projetos de portfólio e é adequada para o modelo de risco deste projeto.

Valor de portfólio: qualquer mudança de infraestrutura passa por revisão do plano antes de ser aplicada. Isso demonstra o ciclo de desenvolvimento com IaC que aparece em ambientes enterprise — não apenas "o Terraform está no repositório", mas "o Terraform é usado com as práticas de revisão adequadas".

### Escopo completo — `terraform apply` automatizado no merge para `main`

Aplica mudanças de infraestrutura automaticamente após o merge. Requer proteção de branch configurada (aprovação de PR obrigatória antes do merge) e gestão cuidadosa de credenciais GCP no GitHub Secrets. Para um projeto solo de portfólio, a distinção entre escopo intermediário e completo é menos relevante — não há segundo revisor para aprovar o merge. O escopo intermediário com `terraform plan` no PR agrega valor de demonstração sem o risco operacional do apply automatizado.

**Decisão**: escopo intermediário — `terraform fmt --check` + `terraform validate` + `terraform plan` no PR, com o output do plan publicado como comentário no PR. O `terraform apply` automatizado no merge foi rejeitado por risco operacional real: com billing ativo no GCP, um apply automatizado mal configurado ou disparado por um merge inadvertido pode criar ou destruir recursos com custo imediato. O escopo mínimo (`fmt` + `validate`) foi rejeitado por insuficiência de demonstração — executar apenas validações estáticas sem se conectar ao GCP não evidencia integração real de IaC com CI/CD. O escopo intermediário equilibra segurança operacional e valor de portfólio: o avaliador vê o output real do `terraform plan` como artefato do PR, demonstrando que o ciclo de revisão de infraestrutura está integrado ao fluxo de desenvolvimento.

---

## Consequências

### Positivas

**Reproducibilidade como propriedade verificável do projeto**: qualquer pessoa com acesso ao repositório e credenciais GCP pode executar `git clone` + `terraform apply` + `docker compose up` e obter um ambiente funcionalmente idêntico ao do autor. Essa propriedade não precisa ser afirmada na documentação — ela pode ser verificada. Para um projeto de portfólio Pleno, a diferença entre "o ambiente está documentado" e "o ambiente pode ser recriado deterministicamente" é o que separa um projeto maduro de um script pessoal bem comentado.

**Detecção de drift antes de qualquer mudança**: `terraform plan` compara o estado registrado com o estado real dos recursos GCP e exibe divergências antes de aplicar qualquer mudança. Se um recurso foi modificado manualmente no console GCP (intencionalmente ou não), o plan expõe a divergência. Scripts shell não têm equivalente — a primeira indicação de que algo está diferente do esperado é quando o script falha ou produz um resultado inesperado.

**Rastreabilidade completa de mudanças de infraestrutura**: cada mudança de configuração de recurso GCP é um commit no repositório. O histórico de git é o histórico da infraestrutura — o que mudou, quando, com qual intenção documentada na mensagem de commit. Não há mudanças de infraestrutura sem rastro.

**`lifecycle` e `prevent_destroy` como proteção contra destruição acidental**: recursos críticos — buckets GCS com dados ingeridos, por exemplo — podem ser protegidos com `lifecycle { prevent_destroy = true }` no HCL. O Terraform recusa `terraform destroy` ou qualquer plan que implique destruição desses recursos, exigindo que a proteção seja removida explicitamente antes da destruição. Essa proteção não existe em scripts shell — um `gcloud storage buckets delete` não tem esse mecanismo.

**Valor de portfólio preciso e verificável**: um avaliador técnico que revisa o repositório e encontra código Terraform com `terraform plan` no CI/CD, resources declarados com princípio de menor privilégio e lifecycle rules de proteção está vendo evidência concreta de conhecimento de IaC — não uma afirmação no README. Essa diferença é o que torna o IaC relevante como demonstração de portfólio.

### Negativas

**Curva de aprendizado do HCL e do ciclo de vida do Terraform**: o Terraform tem seu próprio modelo mental — declarativo, não imperativo; state como fonte de verdade; plan antes de apply. Para quem não trabalhou com IaC antes, essa curva existe e não é trivial. O HCL em si é simples, mas entender como o Terraform gerencia state, detecta drift e aplica mudanças incrementais requer tempo de aprendizado que um script shell não exigiria.

**Overhead de bootstrap do remote state**: se remote state em GCS for adotado, o bucket de state precisa existir antes do primeiro `terraform apply`. Esse bootstrap — seja via `gcloud` CLI ou via Terraform separado — é um passo adicional que precisa estar documentado no README do projeto. Um novo usuário que clone o repositório e execute `terraform apply` sem criar o bucket de state primeiro vai encontrar um erro de backend que não é imediatamente óbvio.

**O state é um artefato que precisa de atenção**: `terraform.tfstate` em local state contém informações de configuração dos recursos — incluindo potencialmente valores sensíveis como chaves de service account se forem geradas pelo Terraform. O arquivo nunca deve ser commitado no repositório. Essa responsabilidade não existe em scripts shell — não há state para gerenciar. `[VERIFICAR]` — confirmar que `terraform.tfstate` e `terraform.tfstate.backup` estão no `.gitignore` do repositório.

**Credenciais GCP para CI/CD**: para executar `terraform plan` no GitHub Actions, o workflow precisa de credenciais GCP. A gestão dessas credenciais — seja via chave JSON em GitHub Secrets ou via Workload Identity Federation — é um passo de configuração adicional que não existe em projetos sem integração de IaC com CI/CD.

---

## Dependências

### Esta ADR depende de

| ADR | Dependência |
|-----|-------------|
| ADR-00 | O objetivo de portfólio para vagas Pleno documentado na ADR-00 é o argumento central que justifica o investimento de implementar IaC em um projeto solo, onde a alternativa (provisionamento manual) teria o mesmo resultado para uma execução, mas zero garantia de reproducibilidade. Sem esse contexto, a escolha do Terraform sobre scripts shell pareceria overhead desnecessário para um projeto de desenvolvimento individual. |
| ADR-03 | Define que o ambiente de execução do PySpark é Google Cloud Dataproc. O Terraform gerencia a configuração base do Dataproc — imagem de cluster, permissões IAM, configurações de rede — a partir das especificações definidas na ADR-03. |
| ADR-04 | Define a estratégia de cluster efêmero com `lifecycle_config.auto_delete_ttl`. O Terraform precisa incluir essa configuração no template de cluster Dataproc para que a Camada 2 de proteção contra cluster órfão esteja ativa. Sem essa configuração no HCL do Terraform, o cluster seria criado sem TTL e dependeria exclusivamente do Airflow para destruição. |
| ADR-06 | Define que o Airflow roda em VM Compute Engine e2-medium com Docker Compose. O Terraform provisiona essa VM com as especificações definidas na ADR-06 — tipo de máquina, imagem de OS, regras de firewall para acesso SSH e à porta da interface web do Airflow. |

### Esta ADR não é dependência de nenhuma outra

Nenhuma decisão nas ADRs de ADR-01 a ADR-07 pressupõe a existência da ADR-08 para seu racional interno. A ADR-08 é a última peça da arquitetura — ela consome decisões de outros componentes, não as produz.

---

## Referências

- ADR-00: Contexto Global e Constraints do Projeto
- ADR-03: Ambiente de Execução do PySpark — Google Cloud Dataproc
- ADR-04: Ciclo de Vida do Cluster Dataproc — Efêmero com Defesa em Profundidade contra Cluster Órfão
- ADR-06: Deployment do Airflow — VM Compute Engine e2-medium com Docker Compose
- ADR-07: Arquitetura de Camadas do Pipeline — Padrão Medalhão (Bronze/Silver/Gold)
- [Terraform — Language Overview (HCL)](https://developer.hashicorp.com/terraform/language)
- [Terraform — State](https://developer.hashicorp.com/terraform/language/state)
- [Terraform — Backend Configuration (GCS)](https://developer.hashicorp.com/terraform/language/backend/gcs)
- [Terraform — `lifecycle` Meta-Argument](https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle)
- [Google Provider for Terraform — `google_compute_instance`](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance)
- [Google Provider for Terraform — `google_storage_bucket`](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket)
- [Google Provider for Terraform — `google_project_iam_binding`](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/google_project_iam_binding)
- [Google Provider for Terraform — `google_service_account`](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/google_service_account)
- [GitHub Actions — google-github-actions/auth (Workload Identity Federation)](https://github.com/google-github-actions/auth)
- [Pulumi — Concepts](https://www.pulumi.com/docs/concepts/)
