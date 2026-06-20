COMPOSE  = docker compose -f docker-compose.yml

init:
	$(COMPOSE) down -v --rmi all --remove-orphans 2>/dev/null || true
	rm -rf src
	mkdir -p src
	docker run --rm -v "$$(pwd)/src:/app" composer create-project --prefer-dist laravel/laravel .
	cp .env.example .env
	cp .env src/.env
	$(COMPOSE) build --no-cache --pull
	$(COMPOSE) up -d
	$(COMPOSE) exec -u www-data app composer install --no-interaction
	$(COMPOSE) exec -u www-data app composer require tymon/jwt-auth --no-interaction
	rm -rf src/resources/js src/resources/css src/resources/views src/node_modules
	rm -f src/vite.config.js src/package.json src/package-lock.json
	rm -f src/webpack.mix.js src/postcss.config.js src/tailwind.config.js
	$(COMPOSE) exec -u www-data app sh -c " \
		php artisan key:generate && \
		php artisan jwt:secret --force && \
		php artisan migrate:fresh --seed --force && \
		php artisan storage:link --force"
	git add -A

up:
	@[ -f src/.env ] || cp .env src/.env
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

down-v:
	$(COMPOSE) down -v

build:
	$(COMPOSE) build

restart:
	$(COMPOSE) restart
ps:
	$(COMPOSE) ps

logs:
	$(COMPOSE) logs -f


# =============================================================================
# Database
# =============================================================================

migrate:
	$(COMPOSE) exec app php artisan migrate --force

seed:
	$(COMPOSE) exec app php artisan db:seed --force

fresh:
	$(COMPOSE) exec app php artisan migrate:fresh --force

migrate-fresh:
	$(COMPOSE) exec app php artisan migrate:fresh --seed --force

artisan:
	$(COMPOSE) exec app php artisan $(cmd)

tinker:
	$(COMPOSE) exec app php artisan tinker

bash:
	$(COMPOSE) exec app sh

db:
	$(COMPOSE) exec db mariadb -u $${DB_USERNAME:-application} -p$${DB_PASSWORD:-secret} $${DB_DATABASE:-application}


# =============================================================================
# Code quality
# =============================================================================

lint:
	$(COMPOSE) exec app vendor/bin/php-cs-fixer fix --dry-run --diff

fix:
	$(COMPOSE) exec app vendor/bin/php-cs-fixer fix

analyse:
	$(COMPOSE) exec app vendor/bin/phpstan analyse --memory-limit=512M

baseline:
	$(COMPOSE) exec app vendor/bin/phpstan analyse --generate-baseline --memory-limit=512M

ide-helper:
	$(COMPOSE) exec -u root app sh -c " \
		php artisan ide-helper:generate && \
		php artisan ide-helper:models --nowrite && \
		php artisan ide-helper:meta && \
		chown -R www-data:www-data /var/www/html"

# =============================================================================
# Tests
# =============================================================================

test:
	$(COMPOSE) exec app ./vendor/bin/phpunit

test-coverage:
	$(COMPOSE) exec app XDEBUG_MODE=coverage ./vendor/bin/phpunit --coverage-html coverage

test-filter:
	$(COMPOSE) exec app ./vendor/bin/phpunit --filter=$(filter)

test-suite:
	$(COMPOSE) exec app ./vendor/bin/phpunit --testsuite=$(suite)

# =============================================================================
# Misc
# =============================================================================

telescope-clear:
	$(COMPOSE) exec app php artisan telescope:clear