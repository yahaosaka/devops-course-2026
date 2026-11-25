# 10. Ansible

Целевой узел — Ubuntu Server 24.04 Noble amd64, управляющий узел — отдельный
контейнер Ubuntu с Ansible. Используйте каталог ansible в файловой системе
Linux. Стенд подключается через NAT виртуальной машины QEMU в WSL. С управляющего контейнера SSH
доступен на host.docker.internal:2223, Nginx — на host.docker.internal:8087.
На Windows эти порты доступны на 127.0.0.1. Для стенда с Host-only замените
ansible_host, ansible_port и app_proxy_port в обоих inventory.
Bootstrap подключается как student. Для prod используются devops и локальный
ключ ~/.ssh/devops_vm. Ключ хоста сверяется и сохраняется в known_hosts.
На лабораторной VM зеркала archive.ubuntu.com и security.ubuntu.com
указаны в ubuntu.sources с HTTPS, поскольку HTTP на этом сетевом маршруте
превышал время ожидания.

Роль base устанавливает Docker и его зависимости. Роль ssh устанавливает
открытый ключ, настраивает SSH, sudo и UFW. Роль nginx публикует сервис на 80.
Роль app загружает образ ghcr.io/yahaosaka/devops-ci-app по полному SHA из
group_vars/all.yml и поднимает порт 5000 только на loopback. Для загрузки
образа доступ должен быть предоставлен реестром. Проверка готовности — /health.

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
ansible-inventory -i inventory/bootstrap.ini --graph
ansible-playbook site.yml --syntax-check
ansible-playbook -i inventory/bootstrap.ini site.yml --ask-pass --ask-become-pass
ansible-playbook -i inventory/prod.ini site.yml
ansible-playbook -i inventory/prod.ini verify.yml
```

Для bootstrap с уже установленным ключом добавьте ansible_private_key_file
в bootstrap.ini и уберите --ask-pass. Выполните два prod-прогона. Во втором
ожидается changed=0. Выполните verify.yml до и после временной остановки
контейнера; восстановите сервис командой ansible-playbook site.yml.

Для drift измените sites-available/devops-ci-app и остановите контейнер,
затем запустите site.yml. Проверьте ответ Nginx и changed у задач шаблона и
контейнера. Для теста отсутствующего тега используйте уникальную 40-значную
строку hex через -e app_tag=..., проверьте остановку на pull и сохранение
прежнего контейнера, затем повторите прогон с обычным тегом.
