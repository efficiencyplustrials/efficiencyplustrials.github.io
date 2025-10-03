org2md_shell_loop: archive.org todo.org
	@for f in $^; do \
		echo "Processing $$f"; \
		pandoc $$f.org -t markdown --output $$f.qmd

	done

org2md: *.org
	$(foreach f, $^, pandoc $f -t markdown --output $(f:org=qmd);)
#	pandoc todo.org -t markdown --output todo.qmd

deploy: org2md
	Rscript -e 'library(rsconnect); addServer(url = "https://rconnect.jnj.com"); connectApiUser(apiKey = "zMeWPJ7dV5VVqNpNVqiId8xsiJSXQzvu"); deployDoc(doc = "index.qmd", appName = "EfficiencyPlus", appTitle = "EfficiencyPlus meeting agenda")'

learn:
	Rscript -e 'library(rsconnect); addServer(url = "https://rconnect.jnj.com"); connectApiUser(apiKey = "zMeWPJ7dV5VVqNpNVqiId8xsiJSXQzvu"); deployDoc(doc = "learn_quarto.qmd", appName = "learn", appTitle = "Learn Quarto")'
