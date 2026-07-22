include config.env
export

CONFIGMAP ?= t3-code-editor-definition
DEVFILE ?= t3-code-editor-devfile.yaml

.PHONY: build push register unregister devfile

build:
	podman build -t $(IMAGE) .

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
