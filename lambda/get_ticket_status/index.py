"""Tool Lambda del agente, expuesta como target de AgentCore Gateway (Módulo
5): consulta el estado de un ticket.

Ver create_ticket/index.py para el contrato de evento/respuesta que usa
AgentCore Gateway (distinto al de Bedrock Agents Classic).
"""

import os

import boto3

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TICKETS_TABLE_NAME"])


def lambda_handler(event, context):
    ticket_id = event.get("ticket_id")

    item = table.get_item(Key={"ticket_id": ticket_id}).get("Item")
    if item is None:
        return {"error": f"No existe un ticket con id {ticket_id}"}

    return {"ticket_id": item["ticket_id"], "status": item["status"]}
