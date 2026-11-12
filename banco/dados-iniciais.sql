INSERT INTO servicos (nome, duracao_min) VALUES
    ('Corte',      30),
    ('Escova',     45),
    ('Hidratação', 60),
    ('Manicure',   40)
ON CONFLICT (nome) DO NOTHING;

INSERT INTO profissionais (nome) VALUES
    ('Ana'),
    ('Bruno'),
    ('Carla')
ON CONFLICT (nome) DO NOTHING;
