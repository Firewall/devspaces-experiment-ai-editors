include config.env
export

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

.PHONY: t3-build t3-push t3-register t3-unregister t3-devfile \
        chamber-build chamber-push chamber-register chamber-unregister chamber-devfile \
        orca-build orca-push orca-register orca-unregister orca-devfile \
        orca-deploy orca-teardown \
        vscode-build vscode-push vscode-deploy vscode-test vscode-teardown \
        vscode-register vscode-unregister vscode-devfile

# === T3 Code targets ===
t3-build:
	podman build --platform linux/amd64 -f $(T3_DIR)/Containerfile -t $(T3_IMAGE) .

t3-push:
	podman push $(T3_IMAGE)

t3-devfile:
	envsubst '$$T3_IMAGE' < $(T3_DEVFILE) > $(T3_DIR)/devfile-rendered.yaml

t3-register: t3-devfile
	oc create configmap $(T3_CONFIGMAP) \
	  --from-file=$(T3_DIR)/devfile-rendered.yaml \
	  -n $(NAMESPACE)
	oc label configmap $(T3_CONFIGMAP) \
	  app.kubernetes.io/part-of=che.eclipse.org \
	  app.kubernetes.io/component=editor-definition \
	  -n $(NAMESPACE)
	@rm -f $(T3_DIR)/devfile-rendered.yaml

t3-unregister:
	oc delete configmap $(T3_CONFIGMAP) -n $(NAMESPACE)

# === OpenChamber targets ===
chamber-build:
	podman build --platform linux/amd64 -f $(CHAMBER_DIR)/Containerfile -t $(OPENCHAMBER_IMAGE) .

chamber-push:
	podman push $(OPENCHAMBER_IMAGE)

chamber-devfile:
	envsubst '$$OPENCHAMBER_IMAGE $$GOOGLE_CLOUD_PROJECT $$CLOUD_ML_REGION $$OPENCHAMBER_UI_PASSWORD' < $(CHAMBER_DEVFILE) > $(CHAMBER_DIR)/devfile-rendered.yaml

chamber-register: chamber-devfile
	oc create configmap $(CHAMBER_CONFIGMAP) \
	  --from-file=$(CHAMBER_DIR)/devfile-rendered.yaml \
	  -n $(NAMESPACE)
	oc label configmap $(CHAMBER_CONFIGMAP) \
	  app.kubernetes.io/part-of=che.eclipse.org \
	  app.kubernetes.io/component=editor-definition \
	  -n $(NAMESPACE)
	@rm -f $(CHAMBER_DIR)/devfile-rendered.yaml

chamber-unregister:
	oc delete configmap $(CHAMBER_CONFIGMAP) -n $(NAMESPACE)

# === Orca targets ===
orca-build:
	podman build --platform linux/amd64 -f $(ORCA_DIR)/Containerfile -t $(ORCA_IMAGE) .

orca-push:
	podman push $(ORCA_IMAGE)

orca-devfile:
	envsubst '$$ORCA_IMAGE $$GOOGLE_CLOUD_PROJECT $$CLOUD_ML_REGION $$ORCA_PAIRING_ADDRESS' < $(ORCA_DEVFILE) > $(ORCA_DIR)/devfile-rendered.yaml

orca-register: orca-devfile
	oc create configmap $(ORCA_CONFIGMAP) \
	  --from-file=$(ORCA_DIR)/devfile-rendered.yaml \
	  -n $(NAMESPACE)
	oc label configmap $(ORCA_CONFIGMAP) \
	  app.kubernetes.io/part-of=che.eclipse.org \
	  app.kubernetes.io/component=editor-definition \
	  -n $(NAMESPACE)
	@rm -f $(ORCA_DIR)/devfile-rendered.yaml

orca-deploy:
	$(ORCA_DIR)/deploy.sh

orca-teardown:
	$(ORCA_DIR)/teardown.sh

orca-unregister:
	oc delete configmap $(ORCA_CONFIGMAP) -n $(NAMESPACE)

# === VS Code Agent Host targets ===
vscode-build:
	podman build --platform linux/amd64 -f $(VSCODE_DIR)/Containerfile -t $(AGENT_HOST_IMAGE) .

vscode-push:
	podman push $(AGENT_HOST_IMAGE)

vscode-devfile:
	envsubst '$$AGENT_HOST_IMAGE' < $(VSCODE_DEVFILE) > $(VSCODE_DIR)/devfile-rendered.yaml

vscode-register: vscode-devfile
	oc create configmap $(VSCODE_CONFIGMAP) \
	  --from-file=$(VSCODE_DIR)/devfile-rendered.yaml \
	  -n $(NAMESPACE)
	oc label configmap $(VSCODE_CONFIGMAP) \
	  app.kubernetes.io/part-of=che.eclipse.org \
	  app.kubernetes.io/component=editor-definition \
	  -n $(NAMESPACE)
	@rm -f $(VSCODE_DIR)/devfile-rendered.yaml

vscode-deploy:
	$(VSCODE_DIR)/deploy.sh

vscode-test:
	$(VSCODE_DIR)/test.sh

vscode-teardown:
	$(VSCODE_DIR)/teardown.sh

vscode-unregister:
	oc delete configmap $(VSCODE_CONFIGMAP) -n $(NAMESPACE)
