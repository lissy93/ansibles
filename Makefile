.PHONY: help first-apply apply setup requirements lint install-ansible install-lint check-env encrypt decrypt $(ROLE_TAGS) $(PLAYBOOKS)

#––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
# Variables
PYTHON		  		:= python3
PIP			 				:= pip3
ANSIBLE_PLAYBOOK:= ansible-playbook
ANSIBLE_LINT		:= ansible-lint
GALAXY		  		:= ansible-galaxy
PLAYBOOK				:= playbooks/all.yml
BECOME		  		:= --ask-become-pass
AS_ROOT		 			:= --extra-vars "ansible_user=root ansible_port=22"

# List of all "role" tags
ROLE_TAGS = docker \
	timezone \
	users \
	ssh \
	hostname \
	firewall \
	fail2ban \
	dotfiles \
	monit \
	cockpit \
	borg \
	maldet \
	lynis \
	system-tuning \
	node_exporter \
	prometheus \
	loki \
	promtail \
	grafana

# List all available playbooks (from playbooks directory)
PLAYBOOKS = $(shell find playbooks -name '*.yml' -type f | sed 's|playbooks/||;s|\.yml||')

#––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
help:
		@echo "Usage:"
		@echo	"  make setup         # install pip deps, galaxy requirements, ansible-lint"
		@echo "  make requirements  # install ansible-galaxy roles from requirements.yml"
		@echo "  make lint          # run ansible-lint on your playbooks"
		@echo "  make decrypt       # sops-decrypt inventory secrets (after a clone)"
		@echo "  make encrypt       # sops-encrypt inventory secrets (before a commit)"
		@echo "  make first-apply   # Initial bootstrap (root-only, before any users exist)"
		@echo "  make apply         # run all roles"
		@echo "  make <role>        # run one tagged role"
		@echo "  make <playbook>    # run one tagged category"
		@echo
	@echo "Available playbooks: $(PLAYBOOKS)"
	@echo "Available roles: $(ROLE_TAGS)"

#––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
# Environment checks
check-env:
	@command -v $(PYTHON) >/dev/null 2>&1 || { \
	  echo >&2 "Error: $(PYTHON) not found. Please install Python 3."; \
	  exit 1; \
	}
	@command -v $(PIP) >/dev/null 2>&1 || { \
	  echo >&2 "Error: $(PIP) not found. Please install pip for Python 3."; \
	  exit 1; \
	}

check-ansible:
	@command -v $(ANSIBLE_LINT) >/dev/null 2>&1 || { \
	  echo >&2 "Error: $(ANSIBLE_LINT) not found. Run `make install-lint`"; \
	  exit 1; \
	}
	@command -v $(ANSIBLE_PLAYBOOK) >/dev/null 2>&1 || { \
	  echo >&2 "Error: $(ANSIBLE_PLAYBOOK) not found. Run `make install-ansible`"; \
	  exit 1; \
	}

#––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
# pip-based installs
install-ansible: check-env
	@echo "Installing Ansible via pip..."
	$(PIP) install --user ansible

install-lint: check-env
	@echo "Installing ansible-lint via pip..."
	$(PIP) install --user ansible-lint

#––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
# Galaxy roles
requirements: check-env check-ansible
	@echo "Installing Ansible Galaxy roles from requirements.yml..."
	$(GALAXY) install -r requirements.yml

#––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
# Combined setup
setup: check-env install-ansible install-lint requirements
	@echo "✔️  Environment is ready - Ansible, ansible-lint, and Galaxy roles installed."

#––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
# Linting
lint: check-ansible
	@echo "Running ansible-lint..."
	$(ANSIBLE_LINT) playbooks/

#––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
# Existing targets

first-apply first-run:
	$(ANSIBLE_PLAYBOOK) $(PLAYBOOK) $(AS_ROOT)

apply run:
	$(ANSIBLE_PLAYBOOK) $(PLAYBOOK) $(BECOME)

# pattern rule: `make docker` → ansible-playbook ... --tags docker
$(ROLE_TAGS):
	$(ANSIBLE_PLAYBOOK) $(PLAYBOOK) $(BECOME) --tags $@

# This runs a specific playbook.
# E.g. `make monitoring` → ansible-playbook ./playbooks/monitoring.yml
$(PLAYBOOKS):
	$(ANSIBLE_PLAYBOOK) ./playbooks/$(@).yml $(BECOME)

#------------------------------------------------------------------------------
# Secrets (SOPS + age). Key at ~/.config/sops/age/keys.txt
encrypt:
	@command -v sops >/dev/null || { echo "sops not found"; exit 1; }
	@for f in inventories/*/host_vars/*.yml; do \
		case "$$f" in *.sops.yml) continue;; esac; \
		[ -e "$$f" ] || continue; \
		echo "Encrypting $$f"; \
		sops --encrypt --input-type yaml --output-type yaml "$$f" > "$${f%.yml}.sops.yml"; \
	done

decrypt:
	@command -v sops >/dev/null || { echo "sops not found"; exit 1; }
	@for f in inventories/*/host_vars/*.sops.yml; do \
		[ -e "$$f" ] || continue; \
		echo "Decrypting $$f"; \
		sops --decrypt --input-type yaml --output-type yaml "$$f" > "$${f%.sops.yml}.yml"; \
	done
