# "Init" container to prepare wordpress core
FROM alpine:latest as downloader

ENV WORDPRESS_VERSION 5.1.1
ENV WORDPRESS_SHA1 f1bff89cc360bf5ef7086594e8a9b68b4cbf2192

# Download Wordpress to /tmp for further processing
RUN set -ex; \
    apk add --no-cache curl; \
	curl -o wordpress.tar.gz -fSL "https://wordpress.org/wordpress-${WORDPRESS_VERSION}.tar.gz"; \
	echo "$WORDPRESS_SHA1 *wordpress.tar.gz" | sha1sum -c -; \
	tar -xzf wordpress.tar.gz -C /tmp;

WORKDIR /tmp/wordpress/

# We are going to remove all default plugins and themes that are shipped with Wordpress. Also some other non-core files.
# These are directories yet we maintain the default index.php for security in the themes and plugins dirs
RUN find ./wp-content/themes/ -maxdepth 1 -mindepth 1 -type d -exec rm -r {} \;; \
    find ./wp-content/plugins/ -maxdepth 1  -mindepth 1 -type d -exec rm -r {} \;; \
    rm wp-config-sample.php; \
    rm wp-content/plugins/hello.php; \
    rm readme.html

# Starting the actual container
FROM php:7.3-apache

# Basic requirements
RUN set -ex; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	\
	apt-get update; \
	apt-get install -y --no-install-recommends \
		libjpeg-dev \
		libpng-dev \
		libzip-dev \
        less \
	; \
	\
	docker-php-ext-configure gd --with-png-dir=/usr --with-jpeg-dir=/usr; \
	docker-php-ext-install gd mysqli opcache zip; \
	\
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark; \
	ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
		| awk '/=>/ { print $3 }' \
		| sort -u \
		| xargs -r dpkg-query -S \
		| cut -d: -f1 \
		| sort -u \
		| xargs -rt apt-mark manual; \
	\
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*

# Configs

RUN { \
		echo 'opcache.memory_consumption=128'; \
		echo 'opcache.interned_strings_buffer=8'; \
		echo 'opcache.max_accelerated_files=4000'; \
		echo 'opcache.revalidate_freq=2'; \
		echo 'opcache.fast_shutdown=1'; \
		echo 'opcache.enable_cli=1'; \
	} > /usr/local/etc/php/conf.d/opcache-recommended.ini

RUN { \
		echo 'error_reporting = 4339'; \
		echo 'display_errors = Off'; \
		echo 'display_startup_errors = Off'; \
		echo 'log_errors = On'; \
		echo 'error_log = /dev/stderr'; \
		echo 'log_errors_max_len = 1024'; \
		echo 'ignore_repeated_errors = On'; \
		echo 'ignore_repeated_source = Off'; \
		echo 'html_errors = Off'; \
	} > /usr/local/etc/php/conf.d/error-logging.ini

RUN a2enmod rewrite expires

# Define volumes, workdirs and prepare wp
VOLUME /var/www/html/wp-content/uploads

WORKDIR /var/www/html/

COPY --from=downloader /tmp/wordpress/ /var/www/html/
COPY wp-config.conf wp-config.php

COPY app/.htaccess .htaccess
COPY app/plugins wp-content/plugins/
COPY app/themes  wp-content/themes/

RUN chown www-data:www-data . -R

COPY docker-entrypoint.sh /usr/local/bin/

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]