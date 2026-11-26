-- Everesting pasa a llamarse Tenzing (el id interno se mantiene).
UPDATE `badges` SET `name` = 'Tenzing', `description` = 'La altura del Everest, 8.849 m de desnivel positivo, en una sola actividad. Por Tenzing Norgay.' WHERE `id` = 'everesting';--> statement-breakpoint
UPDATE `challenges` SET `title` = 'Tenzing', `description` = 'La altura del Everest, 8.849 m de desnivel positivo, en una sola actividad. En honor a Tenzing Norgay, que la subió con Hillary en 1953.' WHERE `id` = 'official-legend-everesting';
