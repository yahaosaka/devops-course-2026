# Управление учебной VM через Ansible

Управляющий узел — Linux или Ubuntu в WSL. Управляемый узел — Ubuntu
Server 24.04 amd64. Укажите реальный Host-only IP в обоих inventory.
Открытый ключ читается из ~/.ssh/devops_vm.pub управляющего узла.
Для первой установки укажите в group_vars/all.yml полный SHA
опубликованного образа ghcr.io/yahaosaka/devops-ci-app.

- base устанавливает Docker Engine и системные зависимости.
- ssh создаёт devops, устанавливает ключ и настраивает SSH и UFW.
- nginx обслуживает HTTP на порту 80.
- app запускает контейнер с портом 5000 на loopback VM и проверяет /health.

    cd ansible
    ansible-galaxy collection install -r requirements.yml
    ansible-playbook -i inventory/bootstrap.ini site.yml --ask-pass --ask-become-pass
    ansible-playbook site.yml
    ansible-playbook verify.yml

Проверки на стенде. Сравните PLAY RECAP при первом и повторном запуске.
На учебной VM временно укажите неверный upstream в конфигурации Nginx,
проверьте её и перезагрузите службу. Запустите site.yml и подтвердите восстановление.
Проверьте отсутствующий тег: pull должен завершиться до замены контейнера.
Для отрицательного verify.yml остановите учебный контейнер и затем
восстановите его через site.yml.
