# syntax = docker/dockerfile:1.1-experimental

# ------------------------------
# --- BASE PREPARATION STAGE ---
# ------------------------------
FROM php:7.4-fpm-alpine3.13 AS base

ENV TZ  'Europe/London'

RUN apk update

RUN apk add --update --no-cache \
    openssh-client \
    libzip-dev \
    git \
    zip \
    curl \
    vim \
    bash

RUN apk add --update --no-cache --virtual .build-deps $PHPIZE_DEPS

RUN apk add --no-cache \
    libpng \
    libpng-dev \
    icu-dev \
    bzip2-dev \
    libmemcached-libs \
    libmemcached-dev \
    libssh2-dev \
    libxml2-dev \
    gnu-libiconv

RUN apk add g++ make autoconf

RUN pecl install apcu-5.1.18 \
    && docker-php-ext-install pdo_mysql \
    && docker-php-ext-enable apcu \
    && docker-php-ext-install bcmath \
    && docker-php-ext-install dba \
    && docker-php-ext-install gd \
    && docker-php-ext-install intl \
    && docker-php-ext-install bz2 \
    && docker-php-ext-install soap \
    && pecl install memcached-3.1.5 \
    && docker-php-ext-enable memcached \
    && docker-php-ext-configure opcache --enable-opcache \
    && docker-php-ext-install opcache \
    && docker-php-ext-install zip \
    && pecl install ssh2-1.2 \
    && docker-php-ext-enable ssh2 \
    && apk del libpng-dev \
    && apk del -f .build-deps


# Fix `iconv` issues with Alpine:
ENV LD_PRELOAD /usr/lib/preloadable_libiconv.so php

# ---------------------------
# --- CONFIGURATION STAGE ---
# ---------------------------

FROM base AS configured

# Remove docker.conf to disable access.log
RUN rm /usr/local/etc/php-fpm.d/docker.conf

COPY docker/conf/php.ini $PHP_INI_DIR/php.ini
COPY docker/conf/docker.conf /usr/local/etc/php-fpm.d/zz-docker.conf
COPY docker/conf/opcache.ini $PHP_INI_DIR/conf.d/docker-php-ext-opcache.ini

# ----------------------
# --- COMPOSER STAGE ---
# ----------------------

FROM configured AS composer

RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer --2

# -------------------
# --- BUILD STAGE ---
# -------------------
FROM composer AS build

ARG COMPOSER_ARGS=-o
ARG APP_ENV='prod'

RUN mkdir -p /opt/build
ADD . /opt/build
WORKDIR /opt/build

ENV APP_ENV=$APP_ENV

RUN --mount=type=secret,id=bitbucket,dst=/root/.ssh/id_rsa,mode=0600,required=true composer install ${COMPOSER_ARGS};
RUN rm -rf /opt/build/var/cache/* && mkdir -p /opt/build/var/cache/

# -------------------------
# --- DEVELOPMENT STAGE ---
# -------------------------

FROM composer AS development

RUN pecl install xdebug-2.9.3 \
    && docker-php-ext-enable xdebug

# Disable opcache for local development
RUN mv $PHP_INI_DIR/conf.d/docker-php-ext-opcache.ini $PHP_INI_DIR/conf.d/docker-php-ext-opcache.ini.disabled

COPY dev/config/xdebug.ini $PHP_INI_DIR/conf.d/docker-php-ext-xdebug.ini

WORKDIR /var/www
VOLUME /var/www

# --------------------------------
# --- IMAGE FINALISATION STAGE ---
# --------------------------------
FROM configured
COPY --from=build --chown=82:82 /opt/build /var/www

RUN chmod 755 /var/www

ARG APP_ENV='prod'

ARG BUILD_DATE
ARG BUILD_VERSION

WORKDIR /var/www
VOLUME /var/www

ENV APP_ENV=$APP_ENV
