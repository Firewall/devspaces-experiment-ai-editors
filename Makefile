include config.env
export

# ---- T3 Code ----
CONFIGMAP ?= t3-code-editor-definition
DEVFILE ?= t3-code-editor-devfile.yaml

# ---- OpenChamber ----
OC_CONFIGMAP ?= openchamber-editor-definition
OC_DEVFILE ?= openchamber-editor-devfile.yaml

.PHONY: build push register unregister devfile \
        oc-build oc-push oc-register oc-unregister oc-devfile

# === T3 Code targets ===
build:
	podman build --platform linux/amd64 -t $(IMAGE) .

push:
	podman push $(IMAGE)

devfile:
	envsubst '$$IMAGE $$GOOGLE_CLOUD_PROJECT $$CLOUD_ML_REGION' < $(DEVFILE) > $(DEVFILE:.yaml=-rendered.yaml)

register: devfile
	oc create configmap $(CONFIGMAP) \
	  --from-file=$(DEVFILE:.yaml=-rendered.yaml) \
	  -n $(NAMESPACE)
	oc label configmap $(CONFIGMAP) \
	  app.kubernetes.io/part-of=che.eclipse.org \
	  app.kubernetes.io/component=editor-definition \
	  -n $(NAMESPACE)
	@rm -f $(DEVFILE:.yaml=-rendered.yaml)

unregister:
	oc delete configmap $(CONFIGMAP) -n $(NAMESPACE)

# === OpenChamber targets ===
oc-build:
	podman build --platform linux/amd64 -t $(OPENCHAMBER_IMAGE) -f Dockerfile.openchamber .

oc-push:
	podman push $(OPENCHAMBER_IMAGE)

oc-devfile:
	envsubst '$$OPENCHAMBER_IMAGE $$GOOGLE_CLOUD_PROJECT $$CLOUD_ML_REGION $$OPENCHAMBER_UI_PASSWORD' < $(OC_DEVFILE) > $(OC_DEVFILE:.yaml=-rendered.yaml)

oc-register: oc-devfile
	oc create configmap $(OC_CONFIGMAP) \
	  --from-file=$(OC_DEVFILE:.yaml=-rendered.yaml) \
	  -n $(NAMESPACE)
	oc label configmap $(OC_CONFIGMAP) \
	  app.kubernetes.io/part-of=che.eclipse.org \
	  app.kubernetes.io/component=editor-definition \
	  -n $(NAMESPACE)
	@rm -f $(OC_DEVFILE:.yaml=-rendered.yaml)

oc-unregister:
	oc delete configmap $(OC_CONFIGMAP) -n $(NAMESPACE)
