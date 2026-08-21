"""Action group Lambda del Bedrock Agent: consulta el estado de un ticket.

Contraparte de read de create_ticket.py: recibe un ticket_id como parámetro y
devuelve su estado actual desde DynamoDB.
"""

import json
import os

import boto3

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TICKETS_TABLE_NAME"])


def lambda_handler(event, context):
    parameters = {p["name"]: p["value"] for p in event.get("parameters", [])}
    ticket_id = parameters.get("ticket_id")

    item = table.get_item(Key={"ticket_id": ticket_id}).get("Item")
    if item is None:
        body = {"error": f"No existe un ticket con id {ticket_id}"}
    else:
        body = {"ticket_id": item["ticket_id"], "status": item["status"]}

    return _agent_response(event, body)


def _agent_response(event, body):
    """Formatea la respuesta en el shape que espera un action group de Bedrock Agents."""
    return {
        "messageVersion": "1.0",
        "response": {
            "actionGroup": event.get("actionGroup"),
            "function": event.get("function"),
            "functionResponse": {
                "responseBody": {"TEXT": {"body": json.dumps(body)}}
            },
        },
    }
