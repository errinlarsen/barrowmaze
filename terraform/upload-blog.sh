#! /usr/bin/env bash

(cd -- ".." && bundle exec jekyll build)

aws s3 sync ../_site s3://errinsgame.rocks/ --delete --profile errinlarsen
