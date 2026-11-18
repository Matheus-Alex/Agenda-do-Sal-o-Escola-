# agenda-salao-escola

**Desafio 03 – Agenda do Salão-Escola** · Cloud Challenge · Senac 2026.2 · Complexidade: avançada

| Grupo nº | Nível de implantação | URL pública (Nível A) | Vídeo do pitch |
|---|---|---|---|
| 03 | A / B / C |  |  |

| Integrante | Papel |
|---|---|
| Matheus | DEV |
| Thales | DADOS |
| Rodrigo | NUVEM |
| Marilia | QA |

---

## 1. Problema e usuário

O salão-escola atende a comunidade com estudantes em estágio supervisionado. Os agendamentos são feitos em um caderno, e é comum dois clientes ficarem marcados no mesmo horário com a mesma profissional.

**Usuário:** recepcionista do salão-escola.
**Objetivo:** agendar sem conflitos e mostrar a agenda do dia de cada profissional, guardando os dados em um banco na nuvem.

## 2. Problemáticas que vamos resolver

| # | Problemática | Como tratamos |
|---|---|---|
| P1 | **Conflito de horário (regra central)** | Mesma profissional não pode ter dois agendamentos ativos sobrepostos. Condição: `novo.inicio < existente.fim AND novo.fim > existente.inicio`. Encostar no fim não é conflito. |
| P2 | Horário de funcionamento | Segunda a sábado, 08:00–20:00. O serviço inteiro precisa caber. Domingo é recusado. |
| P3 | Fim calculado | O servidor calcula `fim = início + duração do serviço`. |
| P4 | Cancelamento libera o horário | Status `cancelado` (exclusão lógica); o horário volta a ficar livre. |
| P5 | Concorrência | Restrição `EXCLUDE USING gist` no banco: com duas requisições simultâneas, uma recebe 201 e a outra 409. |
| P6 | Fuso horário | `TIMESTAMPTZ` + horário enviado com fuso (`2026-11-03T14:00:00-03:00`). Horário de funcionamento validado em America/Recife (UTC−3). |
| P7 | Persistência e segurança | Banco gerenciado, `DATABASE_URL` em variável de ambiente, consultas parametrizadas, validação no servidor, erros 400/404/409/503 sem detalhes internos, dados fictícios. |

## 3. Requisitos da ficha e status

| Código | Requisito | Status |
|---|---|---|
| RF1 | Serviços e profissionais fictícios por script SQL de dados iniciais |  |
| RF2 | Criar agendamento (cliente fictício, serviço, profissional, início; fim calculado) |  |
| RF3 | Recusar conflito (**regra central**) |  |
| RF4 | Respeitar horário de funcionamento (seg–sáb, 08:00–20:00) |  |
| RF5 | Cancelar agendamento, liberando o horário |  |
| RF6 | Listar a agenda de um dia por profissional |  |
| — | `GET /health` testando a conexão com o banco |  |
| Extra | Horários livres do dia, busca por cliente |  |

## 4. Arquitetura

```mermaid
flowchart LR
    A[Navegador<br/>HTML + CSS + JS] -->|HTTPS| B[Azure App Service<br/>API + páginas estáticas]
    B -->|DATABASE_URL + SSL| C[(PostgreSQL<br/>Servidor Flexível)]
```

**Decisão justificada:** PostgreSQL em vez de Azure SQL, pois permite `EXCLUDE USING gist` (extensão `btree_gist`, liberada em `azure.extensions`), impedindo sobreposição no próprio banco.

- **Ganhamos:** integridade garantida mesmo com acessos simultâneos; regra central protegida na camada mais confiável.
- **Perdemos:** tempo extra para configurar a extensão; custo por hora do servidor (lembrar de **parar**); regra menos portável para outros bancos.

## 5. Modelo de dados

```sql
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE servicos (
  id SERIAL PRIMARY KEY,
  nome VARCHAR(80) NOT NULL UNIQUE,
  duracao_min INT NOT NULL CHECK (duracao_min BETWEEN 15 AND 240)
);

CREATE TABLE profissionais (
  id SERIAL PRIMARY KEY,
  nome VARCHAR(80) NOT NULL UNIQUE
);

CREATE TABLE agendamentos (
  id SERIAL PRIMARY KEY,
  cliente VARCHAR(100) NOT NULL,
  servico_id INT NOT NULL REFERENCES servicos(id),
  profissional_id INT NOT NULL REFERENCES profissionais(id),
  inicio TIMESTAMPTZ NOT NULL,
  fim TIMESTAMPTZ NOT NULL,
  status VARCHAR(12) NOT NULL DEFAULT 'ativo' CHECK (status IN ('ativo','cancelado')),
  criado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (fim > inicio),
  EXCLUDE USING gist (
    profissional_id WITH =,
    tstzrange(inicio, fim) WITH &&
  ) WHERE (status = 'ativo')
);
```

`tstzrange(inicio, fim)` é semiaberto `[inicio, fim)`: 14:00–14:30 e 14:30–15:00 não colidem.

## 6. Rotas da API

| Método | Rota | Função | Respostas |
|---|---|---|---|
| GET | `/health` | Testa o banco; devolve `iniciado_em` | 200 / 503 |
| GET | `/servicos` | Lista serviços | 200 |
| GET | `/profissionais` | Lista profissionais | 200 |
| POST | `/agendamentos` | Cria agendamento | 201 / 400 / 404 / 409 |
| GET | `/agendamentos?data=AAAA-MM-DD&profissional_id=N` | Agenda do dia | 200 / 400 |
| PATCH | `/agendamentos/:id/cancelar` | Cancela | 200 / 404 / 409 |

**Ordem no POST:** validar entradas (400) → buscar serviço e profissional (404) → calcular fim → validar dia e horário (400) → inserir; violação de exclusão (`23P01`) vira 409; banco fora do ar vira 503 com mensagem genérica.

Requisições prontas: [`requisicoes.http`](requisicoes.http) _(a criar)_.

## 7. Como executar

**Variáveis de ambiente** (copie `.env.example` para `.env`; o `.env` nunca vai para o Git):

```env
DATABASE_URL=postgres://USUARIO:SENHA@SERVIDOR.postgres.database.azure.com:5432/BANCO?sslmode=require
PORT=3000
TZ_NEGOCIO=America/Recife
```

**Banco:**

```bash
psql "$DATABASE_URL" -f banco/schema.sql
psql "$DATABASE_URL" -f banco/dados-iniciais.sql
```

**Aplicação:** _(preencher conforme a linguagem escolhida)_

```bash
npm install
npm start
```

**Nível C:** plano de implantação na Azure _(preencher se aplicável)_.

## 8. Casos de teste

Cenário: **Ana tem um corte de 30 min às 14:00.**

| Caso | Ação | Esperado | Obtido |
|---|---|---|---|
| CA1 | Ana às 14:15 | 409 (sobreposição) | _ |
| CA2 | Ana às 14:30 | 201 (encostar não é conflito) | _ |
| CA3 | Bruno às 14:15 | 201 (outra profissional) | _ |
| CA4 | Cancelar o das 14:00 e agendar Ana às 14:00 | 201 | _ |
| CA5a | Escova (45 min) às 19:45 | 400 (terminaria às 20:30) | _ |
| CA5b | Agendamento em domingo | 400 | _ |
| N1 | Serviço inexistente | 404 | _ |
| N2 | Profissional inexistente | 404 | _ |
| N3 | Cliente vazio | 400 | _ |
| N4 | Data/hora inválida | 400 | _ |
| N5 | Cancelar id inexistente | 404 | _ |
| N6 | Cancelar já cancelado | 409 | _ |
| N7 | Banco fora do ar | 503 | _ |
| CONC | Duas requisições simultâneas no mesmo horário | uma 201 e outra 409 | _ |

## 9. Prova de persistência

Registro: `GXX-PALAVRA` (palavra anunciada pelo professor às 19h55).

| Print | Descrição | Arquivo |
|---|---|---|
| 1 | Listagem pela aplicação | `evidencias/print1-listagem.png` |
| 2 | `iniciado_em` em `/health` (antes) | `evidencias/print2-health-antes.png` |
| 3 | Após reiniciar: `iniciado_em` mudou e o registro continua | `evidencias/print3-apos-reinicio.png` |
| 4 | Mesma linha em consulta direta ao banco | `evidencias/print4-consulta-banco.png` |

Nível A: registro `PROF-HHMM` criado pelo professor — _anexar print_.

## 10. Evidências obrigatórias

- [ ] **E1** Ambiente (URL pública ou descrição)
- [ ] **E2** Quatro prints da prova de persistência
- [ ] **E3** Casos de teste (≥ 5, sendo 2 negativos)
- [ ] **E4** Diagrama de arquitetura (seção 4)
- [ ] **E5** Variáveis de ambiente com valor oculto e `.gitignore` com `.env`
- [ ] **E6** README completo e link do pitch de 90 s
- [ ] **Específicas:** tabela de testes CA1–CA5 e print da agenda do dia

## 11. Decisões do grupo

1. **Conflito na aplicação ou no banco?** No banco (`EXCLUDE`); a aplicação só valida antes para dar mensagens amigáveis.
2. **Duas recepcionistas ao mesmo tempo?** A restrição serializa a disputa: uma recebe 201, a outra 409.
3. **UTC ou horário local?** Guardamos em `TIMESTAMPTZ`; validamos e exibimos em America/Recife (UTC−3).
4. **Exclusão lógica?** Sim, `cancelado` preserva o histórico e libera o horário via restrição parcial (`WHERE status = 'ativo'`).

## 12. Dificuldade superada

| Problema | Diagnóstico | Causa | Solução |
|---|---|---|---|
| _preencher_ | _preencher_ | _preencher_ | _preencher_ |

**Dificuldades previstas:**

| Problema | Causa provável | Solução planejada |
|---|---|---|
| Agenda "anda" 3 horas | UTC no App Service | `TIMESTAMPTZ` e horário com fuso |
| Bug no limite 14:30 | `<=` em vez de `<` | Intervalo semiaberto; teste do CA2 |
| `EXCLUDE` falha ao criar | `btree_gist` não liberada | Liberar em `azure.extensions` e reiniciar |
| `/health` com timeout | Firewall do banco | Permitir serviços do Azure e adicionar IP |
| `password authentication failed` | Caractere especial sem codificação | Codificar a senha na URL |

## 13. Limitações conhecidas e próximos passos

- Sem login: qualquer recepcionista acessa tudo.
- Cliente identificado apenas por nome fictício.
- Próximos: horários livres do dia por serviço, busca por cliente, agenda visual por profissional.

## 14. Estrutura do repositório

```
agenda-salao-escola/
├── README.md
├── .gitignore            # inclui .env
├── .env.example          # nomes das variáveis, com valores falsos
├── requisicoes.http
├── banco/
│   ├── schema.sql
│   └── dados-iniciais.sql
├── evidencias/           # prints com data e hora visíveis
├── public/               # index.html, style.css, app.js
└── src/                  # código da API
```

> Somente dados fictícios: nomes inventados e e-mails
