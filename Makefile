include config.env
export

# ---- T3 Code ----
T3_DIR = t3-code
T3_CONFIGMAP ?= t3-code-editor-definition
T3_DEVFILE = $(T3_DIR)/devfile.yaml

# ---- OpenChamber ----
OC_DIR = openchamber
OC_CONFIGMAP ?= openchamber-editor-definition
OC_DEVFILE = $(OC_DIR)/devfile.yaml

.PHONY: t3-build t3-push t3-register t3-unregister t3-devfile \
        oc-build oc-push oc-register oc-unregister oc-devfile

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
oc-build:
	podman build --platform linux/amd64 -t $(OPENCHAMBER_IMAGE) $(OC_DIR)

oc-push:
	podman push $(OPENCHAMBER_IMAGE)

oc-devfile:
	envsubst '$$OPENCHAMBER_IMAGE $$GOOGLE_CLOUD_PROJECT $$CLOUD_ML_REGION $$OPENCHAMBER_UI_PASSWORD' < $(OC_DEVFILE) > $(OC_DIR)/devfile-rendered.yaml

oc-register: oc-devfile
	oc create configmap $(OC_CONFIGMAP) \
	  --from-file=$(OC_DIR)/devfile-rendered.yaml \
	  -n $(NAMESPACE)
	oc label configmap $(OC_CONFIGMAP) \
	  app.kubernetes.io/part-of=che.eclipse.org \
	  app.kubernetes.io/component=editor-definition \
	  -n $(NAMESPACE)
	@rm -f $(OC_DIR)/devfile-rendered.yaml

oc-unregister:
	oc delete configmap $(OC_CONFIGMAP) -n $(NAMESPACE)
