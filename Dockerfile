FROM php:7.2-fpm-alpine3.8

ENV DOCROOT /docroot
WORKDIR $DOCROOT

RUN \
    apk update \
    \
    # install nginx and create default pid directory
    && apk add nginx \
    && mkdir -p /run/nginx \
    \
    # forward nginx logs to docker log collector
    && sed -i -E "s/error_log .+/error_log \/dev\/stderr warn;/" /etc/nginx/nginx.conf \
    && sed -i -E "s/access_log .+/access_log \/dev\/stdout main;/" /etc/nginx/nginx.conf \
    \
    # install php-fpm
    && apk add php7-fpm \
    # make php-fpm listen to not tcp port but unix socket
    && sed -i -E "s/127\.0\.0\.1:9000/\/var\/run\/php-fpm\/php-fpm.sock/" /etc/php7/php-fpm.d/www.conf \
    && mkdir /var/run/php-fpm \
    \
    # install supervisor
    && apk add supervisor \
    && mkdir -p /etc/supervisor.d/ \
    \
    # remove caches to decrease image size
    && rm -rf /var/cache/apk/*

RUN apk add --no-cache \
        bash icu-dev gettext-dev postgresql-dev libxml2-dev libxslt-dev \
        freetype libpng libjpeg-turbo freetype-dev libpng-dev libjpeg-turbo-dev \
    && docker-php-ext-configure gd \
        --with-gd \
        --with-freetype-dir=/usr/include/ \
        --with-png-dir=/usr/include/ \
        --with-jpeg-dir=/usr/include/ \
    && NPROC=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || 1) \
    \
    && docker-php-ext-install -j${NPROC} gd \
    && docker-php-ext-install \
        bcmath calendar exif gd gettext intl \
        pcntl pdo_pgsql pgsql shmop sockets \
        sysvmsg sysvsem sysvshm wddx xsl zip \
    \
    && apk del --no-cache freetype-dev libpng-dev libjpeg-turbo-dev

# install composer
RUN EXPECTED_SIGNATURE=$(wget -q -O - https://composer.github.io/installer.sig) \
    && php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" \
    && php -r "if (hash_file('SHA384', 'composer-setup.php') === '$EXPECTED_SIGNATURE') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;" \
    && php composer-setup.php --install-dir=/usr/bin --filename=composer \
    && php -r "unlink('composer-setup.php');"

ENV PHP_INI_DIR /etc/php7
ENV NGINX_CONFD_DIR /etc/nginx/conf.d

COPY config/php.ini $PHP_INI_DIR/
COPY config/nginx.conf $NGINX_CONFD_DIR/default.conf
COPY config/supervisor.programs.ini /etc/supervisor.d/
COPY bin/start.sh /bin/

RUN \
    # add non-root user
    # @see https://devcenter.heroku.com/articles/container-registry-and-runtime#run-the-image-as-a-non-root-user
    adduser -D nonroot \
    \
    # followings are just for local environment
    # (on heroku dyno there is no permission problem because most of the filesystem owned by the current non-root user)
    && chmod a+x /bin/start.sh \
    \
    # to update conf files and create temp files under the directory via sed command on runtime
    && chmod -R a+w /etc/php7/php-fpm.d \
    && chmod -R a+w /etc/nginx \
    \
    # to run php-fpm (socker directory)
    && chmod a+w /var/run/php-fpm \
    \
    # to run nginx (default pid directory and tmp directory)
    && chmod -R a+w /run/nginx \
    && chmod -R a+wx /var/tmp/nginx \
    \
    # to run supervisor (read conf and create socket)
    && chmod -R a+r /etc/supervisor* \
    && sed -i -E "s/^file=\/run\/supervisord\.sock/file=\/run\/supervisord\/supervisord.conf/" /etc/supervisord.conf \
    && mkdir -p /run/supervisord \
    && chmod -R a+w /run/supervisord \
    \
    # to output logs
    && chmod -R a+w /var/log \
    \
    # add nonroot to sudoers
    && apk add --update sudo \
    && echo "nonroot ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# copy application code
COPY ./src/. $DOCROOT/

RUN \
    # attempt to composer install
    # (if depends on any commands that don't exist at this time, like npm, explicit doing composer install on downstream Dockerfile is necessary)
    if [ -f "composer.json" ]; then \
        composer install --no-interaction || : \
    ; fi \
    \
    # fix permission of docroot for non-root user
    && chmod -R a+w $DOCROOT

RUN rm /bin/sh && ln -s /bin/bash /bin/sh

USER nonroot

ENTRYPOINT []

CMD ["/bin/start.sh"]
