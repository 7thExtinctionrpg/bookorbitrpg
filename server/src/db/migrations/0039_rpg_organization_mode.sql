ALTER TABLE "libraries" DROP CONSTRAINT "libraries_organization_mode_chk";
--> statement-breakpoint
ALTER TABLE "libraries" ADD CONSTRAINT "libraries_organization_mode_chk" CHECK ("libraries"."organization_mode" in ('book_per_folder', 'book_per_file', 'book_per_file_rpg'));