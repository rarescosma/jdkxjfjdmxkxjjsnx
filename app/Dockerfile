ARG HUB=docker.io
FROM ${HUB}/library/python:3.12.7-slim

WORKDIR /app
COPY ./run.py /app

ENV PYTHONUNBUFFERED=1

CMD ["python3", "/app/run.py"]

