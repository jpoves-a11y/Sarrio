-- Lleva al feed lo que ya existía antes de la fase social: salidas de montaña (o con cimas),
-- ascensiones manuales y emblemas. Idempotente: no duplica lo que ya está.
INSERT INTO `feed_items` (`id`, `actor_id`, `kind`, `ref_id`, `visibility`, `created_at`)
SELECT 'bf-a-' || a.`id`, a.`user_id`, 'activity', a.`id`, a.`visibility`, a.`start_at`
FROM `activities` a
WHERE (a.`sport_type` IN ('hiking', 'mountaineering', 'trail_running', 'snowshoeing', 'backcountry_skiing', 'climbing')
       OR EXISTS (SELECT 1 FROM `ascents` s WHERE s.`activity_id` = a.`id`))
  AND NOT EXISTS (SELECT 1 FROM `feed_items` f WHERE f.`kind` = 'activity' AND f.`ref_id` = a.`id`);--> statement-breakpoint
INSERT INTO `feed_items` (`id`, `actor_id`, `kind`, `ref_id`, `visibility`, `created_at`)
SELECT 'bf-s-' || s.`id`, s.`user_id`, 'ascent', s.`id`, s.`visibility`, s.`summited_at`
FROM `ascents` s
WHERE s.`activity_id` IS NULL
  AND NOT EXISTS (SELECT 1 FROM `feed_items` f WHERE f.`kind` = 'ascent' AND f.`ref_id` = s.`id`);--> statement-breakpoint
INSERT INTO `feed_items` (`id`, `actor_id`, `kind`, `ref_id`, `visibility`, `created_at`)
SELECT 'bf-b-' || ub.`user_id` || '-' || ub.`badge_id`, ub.`user_id`, 'badge', ub.`badge_id`, u.`default_visibility`, ub.`earned_at`
FROM `user_badges` ub JOIN `users` u ON u.`id` = ub.`user_id`
WHERE NOT EXISTS (SELECT 1 FROM `feed_items` f WHERE f.`kind` = 'badge' AND f.`ref_id` = ub.`badge_id` AND f.`actor_id` = ub.`user_id`);
