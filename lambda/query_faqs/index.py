"""Tool Lambda del agente, expuesta como target de AgentCore Gateway (Módulo
5): busca en la Knowledge Base de FAQs (Módulo 4) usando el Retrieve API de
Bedrock.

Esta Lambda no existía en el Módulo 3 — se crea acá porque AgentCore no tiene
un tipo de tool nativo para "Knowledge Base" (a diferencia de Bedrock Agents
Classic, que la conectaba directo vía knowledge_base_association): todo tool
en AgentCore pasa por un Gateway target, así que la Knowledge Base necesita
este puente igual que create_ticket/get_ticket_status.
"""

import os

import boto3

bedrock_agent_runtime = boto3.client("bedrock-agent-runtime")
KNOWLEDGE_BASE_ID = os.environ["KNOWLEDGE_BASE_ID"]


def lambda_handler(event, context):
    query = event.get("query", "")

    response = bedrock_agent_runtime.retrieve(
        knowledgeBaseId=KNOWLEDGE_BASE_ID,
        retrievalQuery={"text": query},
    )

    results = [
        {"text": r["content"]["text"], "score": r.get("score")}
        for r in response.get("retrievalResults", [])
    ]

    return {"results": results}
