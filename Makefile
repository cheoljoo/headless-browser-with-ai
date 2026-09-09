SKILLS_DIR := $(HOME)/.claude/skills
SKILLS     := steel-cdp-browse

.DEFAULT_GOAL := help
.PHONY: help skill-install skill-update skill-uninstall

help:
	@echo "make skill-install   - .claude/skills/{$(SKILLS)} 를 $(SKILLS_DIR)/ 로 설치"
	@echo "                       (설치 후 어느 디렉터리에서든 Claude Code가 이 skill을 호출 가능)"
	@echo "make skill-update    - git pull로 최신화한 뒤 skill-install과 동일하게 다시 설치"
	@echo "make skill-uninstall - 설치된 skill을 $(SKILLS_DIR)/ 에서 제거"

skill-install:
	@mkdir -p $(SKILLS_DIR)
	@for skill in $(SKILLS); do \
		rm -rf $(SKILLS_DIR)/$$skill; \
		cp -r .claude/skills/$$skill $(SKILLS_DIR)/$$skill; \
		echo "$$skill skill 설치: $(SKILLS_DIR)/$$skill"; \
	done
	@echo "cdp_client.js 의존성(ws) 설치 확인 중..."
	@cd scripts && { [ -d node_modules/ws ] || npm install --no-audit --no-fund; }

skill-update: skill-install

skill-uninstall:
	@for skill in $(SKILLS); do \
		rm -rf $(SKILLS_DIR)/$$skill; \
		echo "$$skill skill 제거: $(SKILLS_DIR)/$$skill"; \
	done
