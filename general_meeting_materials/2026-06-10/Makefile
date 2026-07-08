pptx:
	quarto render index.qmd --to pptx

html:
	quarto render index.qmd --to revealjs

deploy: html
	Rscript -e 'library(rsconnect); connectApiUser(server = "rconnect-qa.jnj.com", apiKey = "t7YRfXZzaDOCqeSuwgc2nMZG1mpiIlXc"); deployDoc(doc = "index.qmd", server = "rconnect-qa.jnj.com", appName = "effpgm202606", appTitle = "Efficiency+ General Meeting (Jun 10, 2026)")'
