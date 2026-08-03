.PHONY: help dev-server test-server build-server dev-app test-app build-apk test clean docker-up docker-down

# Цвета для красивого вывода в терминале
CYAN    := \033[36m
GREEN   := \033[32m
YELLOW  := \033[33m
MAGENTA := \033[35m
RESET   := \033[0m
BOLD    := \033[1m

## По умолчанию выводим справочное меню
help:
	@echo ""
	@echo "$(CYAN)$(BOLD)  ___ _  _ _____ ___ ___ ___   _   ___ $(RESET)"
	@echo "$(CYAN)$(BOLD) |_ || || |_   _| __| _ \\ _ \\ /_\\ | _ \\$(RESET)"
	@echo "$(CYAN)$(BOLD)  | || || | | | | _||   /   // _ \\|   /$(RESET)"
	@echo "$(CYAN)$(BOLD) |___|_||_| |_| |___|_|_\\_|_/_/ \\_\\_|_\\$(RESET)"
	@echo ""
	@echo "$(BOLD)Команды управления проектом «ЛК Интерра»:$(RESET)"
	@echo ""
	@echo "  $(YELLOW)$(BOLD)🔹 РАЗРАБОТКА (DEV)$(RESET)"
	@echo "    $(GREEN)make dev-server$(RESET)   - Запустить TypeScript бэкенд (tsx watch)"
	@echo "    $(GREEN)make dev-app$(RESET)      - Запустить Flutter приложение"
	@echo ""
	@echo "  $(YELLOW)$(BOLD)🧪 ТЕСТИРОВАНИЕ И ПРОВЕРКИ (TESTING)$(RESET)"
	@echo "    $(GREEN)make test$(RESET)         - Прогнать тесты сервера (Vitest) и приложения"
	@echo "    $(GREEN)make test-server$(RESET)  - Прогнать тесты бэкенда (Vitest 10/10)"
	@echo "    $(GREEN)make test-app$(RESET)     - Прогнать тесты Flutter приложения"
	@echo "    $(GREEN)make typecheck$(RESET)    - Проверить типы TypeScript"
	@echo ""
	@echo "  $(YELLOW)$(BOLD)📦 СБОРКА И ДЕПЛОЙ (BUILD)$(RESET)"
	@echo "    $(GREEN)make build-server$(RESET) - Собрать бэкенд в dist/"
	@echo "    $(GREEN)make build-apk$(RESET)    - Собрать релизный Android APK"
	@echo "    $(GREEN)make docker-up$(RESET)    - Поднять бэкенд в изолированном Docker"
	@echo "    $(GREEN)make docker-down$(RESET)  - Остановить Docker контейнер"
	@echo "    $(GREEN)make clean$(RESET)        - Очистить артефакты сборки"
	@echo ""

dev-server:
	cd server && npm run dev

dev-app:
	cd app && flutter run

test-server:
	cd server && npm run test

test-app:
	cd app && flutter test

typecheck:
	cd server && npm run typecheck

test: test-server test-app

build-server:
	cd server && npm run build

build-apk:
	cd app && flutter build apk --release

docker-up:
	cd server && docker-compose up -d --build

docker-down:
	cd server && docker-compose down

clean:
	rm -rf server/dist server/node_modules app/build
	@echo "$(GREEN)✔ Артефакты сборки очищены$(RESET)"
