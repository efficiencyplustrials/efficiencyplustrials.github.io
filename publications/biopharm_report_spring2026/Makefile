.PHONY: all clean

all: article.docx

article.docx: article.qmd references.bib QR.png postprocess.py
	quarto render article.qmd --to docx
	python3 postprocess.py

clean:
	rm -f article.docx
