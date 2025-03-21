# Multistage docker file 
# In the BUILD stage we 
# - get the main application with git
# - build all the required extensions
# In the final stage we 
# - copy the pre-build extensions

# syntax = docker/dockerfile:1.2
FROM php:8.2-apache-bookworm AS BUILD
LABEL AUTHOR Lucrasoft
WORKDIR /home

RUN apt-get update -q \
    && apt-get install -y apache2 unzip curl wget \
    && apt-get install -y apt-transport-https lsb-release ca-certificates \
    && wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg \
    && echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list \
    && apt-get update -q

#RUN apt-get update -q \
#    && apt-get install -y php8.2 php8.2-dev php8.2-ldap php8.2-xml php8.2-bcmath php8.2-mbstring php8.2-xml php8.2-curl php8.2-opcache php8.2-readline php8.2-zip

RUN mkdir /tmp/install \ 
    && cd /tmp/install  \
    && curl -LOf https://github.com/phalcon/cphalcon/releases/download/v5.3.1/phalcon-php8.2-nts-ubuntu-gcc-x64.zip \
    && unzip phalcon-php8.2-nts-ubuntu-gcc-x64.zip  \
    && mkdir /usr/lib/php/20220829 \
    && cp phalcon.so /usr/lib/php/20220829 \
    && cd /  \
    && rm -rf /tmp/install \
    && echo "extension=phalcon.so" | tee /etc/php/8.2/apache2/conf.d/30-phalcon.ini \
    && echo "extension=phalcon.so" | tee /etc/php/8.2/cli/conf.d/30-phalcon.ini

RUN echo "extension=mongodb.so" | tee /etc/php/8.2/apache2/conf.d/20-mongodb.ini \
    && echo "extension=mongodb.so" | tee /etc/php/8.2/cli/conf.d/20-mongodb.ini \
    && opcache_path=$(php --ini | grep opcache | awk '{print $NF}' | sed 's/,//') \
    && /bin/echo -e 'opcache.enable=1' >> $opcache_path \
    && /bin/echo -e 'opcache.memory_consumption=192' >> $opcache_path \
    && /bin/echo -e 'opcache.interned_strings_buffer=16' >> $opcache_path \
    && /bin/echo -e 'opcache.max_accelerated_files=100000' >> $opcache_path \
    && /bin/echo -e 'opcache.validate_timestamps=0' >> $opcache_path \
    && /bin/echo -e 'opcache.revalidate_freq=0' >> $opcache_path \
    && /bin/echo -e 'opcache.preload=/var/www/config/preload.php' >> $opcache_path \
    && /bin/echo -e 'opcache.preload_user=www-data' >> $opcache_path \
    && sed -i '/session.cookie_secure =/c session.cookie_secure = On' /etc/php/8.2/apache2/php.ini

RUN curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor \
    && echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] http://repo.mongodb.org/apt/debian bookworm/mongodb-org/7.0 main" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list \
    && apt-get update \
    && apt-get install -y mongodb-org \
    && systemctl start mongod.service \
    && systemctl enable mongod.service

RUN --mount=type=secret,id=mysecret,dst=/var/secret/mysecret \
    && curl -o "/var/www/passwork.zip" "https://portal.passwork.pro/api/download?rc=yes&apikey=$cert" \
    && unzip /var/www/passwork.zip -d /var/www/ \
    && find /var/www/ -type d -exec chmod 755 {} \; \
    && find /var/www/ -type f -exec chmod 644 {} \; \
    && chown -R www-data:www-data /var/www/

RUN /bin/echo -e $' \
<VirtualHost *:80>\n\
    ServerAdmin webmaster@localhost\n\
    DocumentRoot /var/www/public\n\
    <Directory /var/www/public>\n\
        Options FollowSymLinks MultiViews\n\
        AllowOverride All\n\
        Order allow,deny\n\
        allow from all\n\
    </Directory>\n\
    ErrorLog ${APACHE_LOG_DIR}/error.log\n\
    CustomLog ${APACHE_LOG_DIR}/access.log combined\n\
</VirtualHost>\n' >> /etc/apache2/sites-enabled/000-default.conf
    
RUN a2enmod rewrite \
    && service apache2 restart

# setup background tasks with cron
RUN echo '* * * * * bash -l -c "cd /var/www/ && php ./bin/console tasks:run"' > /etc/mycron
RUN crontab -u root /etc/mycron

# a new entrypoint which also starts cron
COPY entrypoint /usr/local/bin/
RUN chmod 775 /usr/local/bin/entrypoint
ENTRYPOINT ["entrypoint"]

CMD ["apache2-foreground"]
