include config.env
export
.DEFAULT_GOAL := t3-build

# ---- T3 Code ----
T3_DIR = t3-code
T3_CONFIGMAP ?= t3-code-editor-definition
T3_DEVFILE = $(T3_DIR)/devfile.yaml

# ---- OpenChamber ----
CHAMBER_DIR = openchamber
CHAMBER_CONFIGMAP ?= openchamber-editor-definition
CHAMBER_DEVFILE = $(CHAMBER_DIR)/devfile.yaml

# ---- Orca ----
ORCA_DIR = orca
ORCA_CONFIGMAP ?= orca-editor-definition
ORCA_DEVFILE = $(ORCA_DIR)/devfile.yaml

# ---- VS Code Agent Host ----
VSCODE_DIR = vs-code-agent-host
VSCODE_CONFIGMAP ?= vs-code-agent-host-editor-definition
VSCODE_DEVFILE = $(VSCODE_DIR)/devfile.yaml

# ---- OpenClaw ----
OPENCLAW_DIR = openclaw
OPENCLAW_CONFIGMAP ?= openclaw-editor-definition
OPENCLAW_DEVFILE = $(OPENCLAW_DIR)/devfile.yaml

# ---- Paseo ----
PASEO_DIR = paseo
PASEO_CONFIGMAP ?= paseo-editor-definition
PASEO_DEVFILE = $(PASEO_DIR)/devfile.yaml

BOB_DIR = bob
BOB_CONFIGMAP ?= bob-editor-definition
BOB_DEVFILE = $(BOB_DIR)/devfile.yaml

.PHONY: check-namespace t3-build t3-push t3-register t3-unregister t3-devfile t3-definition \
        chamber-build chamber-push chamber-register chamber-unregister chamber-devfile chamber-definition \
        orca-build orca-push orca-register orca-unregister orca-devfile orca-definition \
        orca-deploy orca-teardown \
        vscode-build vscode-push vscode-deploy vscode-test vscode-teardown \
        vscode-register vscode-unregister vscode-devfile vscode-definition \
        openclaw-build openclaw-push openclaw-deploy openclaw-teardown \
        openclaw-register openclaw-unregister openclaw-devfile openclaw-definition \
        paseo-build paseo-push paseo-deploy paseo-teardown \
        paseo-register paseo-unregister paseo-devfile paseo-definition \
        bob-build bob-push bob-deploy bob-test bob-teardown bob-register bob-unregister bob-devfile bob-definition

check-namespace:
	@test -n "$(NAMESPACE)" || { echo "Set NAMESPACE in config.env before registering or removing editors."; exit 1; }

# Render an editor definition ConfigMap and apply it. Render into a shell variable
# first so a devfile error stops before any cluster command runs.
define register_editor_definition
definition=$$(python3 shared/render-devfile.py "$(1)" --configmap "$(2)") && \
printf '%s\n' "$$definition" | oc apply -n $(NAMESPACE) -f -
endef

# === T3 Code targets ===
t3-build:
	podman build --platform linux/amd64 -f $(T3_DIR)/Containerfile -t $(T3_IMAGE) .

t3-push:
	podman push $(T3_IMAGE)

t3-devfile:
	python3 shared/render-devfile.py "$(T3_DEVFILE)" --output "$(T3_DIR)/devfile-rendered.yaml"

t3-definition:
	python3 shared/render-devfile.py "$(T3_DEVFILE)" --configmap "$(T3_CONFIGMAP)" \
	  --output "$(T3_DIR)/editor-definition.yaml"

t3-register: check-namespace
	@$(call register_editor_definition,$(T3_DEVFILE),$(T3_CONFIGMAP))

t3-unregister: check-namespace
	oc delete configmap $(T3_CONFIGMAP) -n $(NAMESPACE)

# === OpenChamber targets ===
chamber-build:
	podman build --platform linux/amd64 -f $(CHAMBER_DIR)/Containerfile -t $(OPENCHAMBER_IMAGE) .

chamber-push:
	podman push $(OPENCHAMBER_IMAGE)

chamber-devfile:
	python3 shared/render-devfile.py "$(CHAMBER_DEVFILE)" --output "$(CHAMBER_DIR)/devfile-rendered.yaml"

chamber-definition:
	python3 shared/render-devfile.py "$(CHAMBER_DEVFILE)" --configmap "$(CHAMBER_CONFIGMAP)" \
	  --output "$(CHAMBER_DIR)/editor-definition.yaml"

chamber-register: check-namespace
	@$(call register_editor_definition,$(CHAMBER_DEVFILE),$(CHAMBER_CONFIGMAP))

chamber-unregister: check-namespace
	oc delete configmap $(CHAMBER_CONFIGMAP) -n $(NAMESPACE)

# === Orca targets ===
orca-build:
	podman build --platform linux/amd64 -f $(ORCA_DIR)/Containerfile -t $(ORCA_IMAGE) .

orca-push:
	podman push $(ORCA_IMAGE)

orca-devfile:
	python3 shared/render-devfile.py "$(ORCA_DEVFILE)" --output "$(ORCA_DIR)/devfile-rendered.yaml"

orca-definition:
	python3 shared/render-devfile.py "$(ORCA_DEVFILE)" --configmap "$(ORCA_CONFIGMAP)" \
	  --output "$(ORCA_DIR)/editor-definition.yaml"

orca-register: check-namespace
	@$(call register_editor_definition,$(ORCA_DEVFILE),$(ORCA_CONFIGMAP))

orca-deploy:
	$(ORCA_DIR)/deploy.sh

orca-teardown:
	$(ORCA_DIR)/teardown.sh

orca-unregister: check-namespace
	oc delete configmap $(ORCA_CONFIGMAP) -n $(NAMESPACE)

# === VS Code Agent Host targets ===
vscode-build:
	podman build --platform linux/amd64 -f $(VSCODE_DIR)/Containerfile -t $(AGENT_HOST_IMAGE) .

vscode-push:
	podman push $(AGENT_HOST_IMAGE)

vscode-devfile:
	python3 shared/render-devfile.py "$(VSCODE_DEVFILE)" --output "$(VSCODE_DIR)/devfile-rendered.yaml"

vscode-definition:
	python3 shared/render-devfile.py "$(VSCODE_DEVFILE)" --configmap "$(VSCODE_CONFIGMAP)" \
	  --output "$(VSCODE_DIR)/editor-definition.yaml"

vscode-register: check-namespace
	@$(call register_editor_definition,$(VSCODE_DEVFILE),$(VSCODE_CONFIGMAP))

vscode-deploy:
	$(VSCODE_DIR)/deploy.sh

vscode-test:
	$(VSCODE_DIR)/test.sh

vscode-teardown:
	$(VSCODE_DIR)/teardown.sh

vscode-unregister: check-namespace
	oc delete configmap $(VSCODE_CONFIGMAP) -n $(NAMESPACE)

# === OpenClaw targets ===
openclaw-build:
	podman build --platform linux/amd64 -f $(OPENCLAW_DIR)/Containerfile -t $(OPENCLAW_IMAGE) .

openclaw-push:
	podman push $(OPENCLAW_IMAGE)

openclaw-devfile:
	python3 shared/render-devfile.py "$(OPENCLAW_DEVFILE)" --output "$(OPENCLAW_DIR)/devfile-rendered.yaml"

openclaw-definition:
	python3 shared/render-devfile.py "$(OPENCLAW_DEVFILE)" --configmap "$(OPENCLAW_CONFIGMAP)" \
	  --output "$(OPENCLAW_DIR)/editor-definition.yaml"

openclaw-register: check-namespace
	@$(call register_editor_definition,$(OPENCLAW_DEVFILE),$(OPENCLAW_CONFIGMAP))

openclaw-unregister: check-namespace
	oc delete configmap $(OPENCLAW_CONFIGMAP) -n $(NAMESPACE)

openclaw-deploy:
	$(OPENCLAW_DIR)/deploy.sh

openclaw-teardown:
	$(OPENCLAW_DIR)/teardown.sh

# === Paseo targets ===
paseo-build:
	podman build --platform linux/amd64 -f $(PASEO_DIR)/Containerfile -t $(PASEO_IMAGE) .

paseo-push:
	podman push $(PASEO_IMAGE)

paseo-devfile:
	python3 shared/render-devfile.py "$(PASEO_DEVFILE)" --output "$(PASEO_DIR)/devfile-rendered.yaml"

paseo-definition:
	python3 shared/render-devfile.py "$(PASEO_DEVFILE)" --configmap "$(PASEO_CONFIGMAP)" \
	  --output "$(PASEO_DIR)/editor-definition.yaml"

paseo-register: check-namespace
	@$(call register_editor_definition,$(PASEO_DEVFILE),$(PASEO_CONFIGMAP))

paseo-unregister: check-namespace
	oc delete configmap $(PASEO_CONFIGMAP) -n $(NAMESPACE)

paseo-deploy:
	$(PASEO_DIR)/deploy.sh

paseo-teardown:
	$(PASEO_DIR)/teardown.sh

# === IBM Bob PoC targets ===
bob-build:
	podman build --platform linux/amd64 --target $(or $(BOB_BACKEND),bob) -f $(BOB_DIR)/Containerfile -t $(BOB_IMAGE) .

bob-push:
	podman push $(BOB_IMAGE)

bob-deploy:
	$(BOB_DIR)/deploy.sh

bob-test:
	$(BOB_DIR)/test.sh

bob-teardown:
	$(BOB_DIR)/teardown.sh

bob-devfile:
	python3 shared/render-devfile.py "$(BOB_DEVFILE)" --output "$(BOB_DIR)/devfile-rendered.yaml"

bob-definition:
	python3 shared/render-devfile.py "$(BOB_DEVFILE)" --configmap "$(BOB_CONFIGMAP)" \
	  --output "$(BOB_DIR)/editor-definition.yaml"

bob-register: check-namespace
	@$(call register_editor_definition,$(BOB_DEVFILE),$(BOB_CONFIGMAP))

bob-unregister: check-namespace
	oc delete configmap $(BOB_CONFIGMAP) -n $(NAMESPACE)
