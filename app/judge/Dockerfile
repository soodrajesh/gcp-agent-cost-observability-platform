# Build context: repo root (needs app/pipeline + app/judge + repo-root golden_set/)
FROM python:3.12-slim
WORKDIR /srv
COPY app/judge/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app/pipeline ./pipeline
COPY app/judge ./judge
COPY golden_set /golden_set
ENV PYTHONPATH=/srv
CMD ["python", "judge/run_golden_set.py"]
