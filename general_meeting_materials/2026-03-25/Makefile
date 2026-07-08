pptx:
	quarto render index.qmd --to pptx

html:
	quarto render index.qmd --to revealjs

deploy: html
	Rscript -e 'library(rsconnect); addServer(url = "https://rconnect.jnj.com"); connectApiUser(apiKey = "zMeWPJ7dV5VVqNpNVqiId8xsiJSXQzvu"); deployDoc(doc = "index.qmd", appName = "effpgm202603", appTitle = "Efficiency+ General Meeting (Mar 25, 2026)")'
