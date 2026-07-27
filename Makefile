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

.PHONY: t3-build t3-push t3-register t3-unregister t3-devfile \
        chamber-build chamber-push chamber-register chamber-unregister chamber-devfile

# === T3 Code targets ===
t3-build:
	podman build --platform linux/amd64 -t $(T3_IMAGE) $(T3_DIR)

t3-push:
	podman push $(T3_IMAGE)

t3-devfile:
	envsubst '$$T3_IMAGE $$GOOGLE_CLOUD_PROJECT $$CLOUD_ML_REGION' < $(T3_DEVFILE) > $(T3_DIR)/devfile-rendered.yaml

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
	podman build --platform linux/amd64 -t $(OPENCHAMBER_IMAGE) $(CHAMBER_DIR)

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
