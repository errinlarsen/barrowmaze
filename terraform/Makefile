.PHONY: plan apply destroy init deploy

plan:
	terraform plan -out tfplan

apply:
	terraform apply tfplan

destroy:
	terraform plan -out tfplan -destroy

init:
	terraform init

deploy:
	(cd -- ".." && bundle exec jekyll build)
	aws s3 sync ../_site s3://errinsgame.rocks/ --delete --profile errinlarsen
