CREATE TABLE `activity_tracks` (
	`activity_id` text PRIMARY KEY NOT NULL,
	`encoding` text DEFAULT 'gz-json-v1' NOT NULL,
	`point_count` integer NOT NULL,
	`data` blob NOT NULL,
	FOREIGN KEY (`activity_id`) REFERENCES `activities`(`id`) ON UPDATE no action ON DELETE cascade
);
