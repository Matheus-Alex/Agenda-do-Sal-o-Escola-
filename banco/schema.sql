CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE IF NOT EXISTS servicos (
    id          SERIAL PRIMARY KEY,
    nome        VARCHAR(80) NOT NULL UNIQUE,
    duracao_min INTEGER NOT NULL
                CHECK (duracao_min BETWEEN 15 AND 240)
);

CREATE TABLE IF NOT EXISTS profissionais (
    id    SERIAL PRIMARY KEY,
    nome  VARCHAR(80) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS agendamentos (
    id              SERIAL PRIMARY KEY,
    cliente         VARCHAR(100) NOT NULL,
    servico_id      INTEGER NOT NULL REFERENCES servicos(id),
    profissional_id INTEGER NOT NULL REFERENCES profissionais(id),
    inicio          TIMESTAMPTZ NOT NULL,
    fim             TIMESTAMPTZ NOT NULL,
    status          VARCHAR(10) NOT NULL DEFAULT 'ativo'
                    CHECK (status IN ('ativo', 'cancelado')),
    criado_em       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (fim > inicio),

    CONSTRAINT sem_sobreposicao
        EXCLUDE USING gist (
            profissional_id WITH =,
            tstzrange(inicio, fim, '[)') WITH &&
        ) WHERE (status = 'ativo')
);

CREATE INDEX IF NOT EXISTS idx_agend_prof_inicio
    ON agendamentos (profissional_id, inicio);
