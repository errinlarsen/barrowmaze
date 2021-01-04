.PHONY: plan apply destroy init

plan:
	terraform plan -out tfplan

apply:
	terraform apply tfplan

destroy:
	terraform plan -out tfplan -destroy

init:
	terraform init
