"""Action group Lambda del Bedrock Agent: crea un ticket de soporte.

Bedrock invoca esta función cuando el modelo decide usar la tool "create_ticket"
(definida como action group en el Módulo 5). El evento trae los parámetros que el
modelo extrajo del mensaje del usuario en event["parameters"].
"""

import json
import os
import time
import uuid

import boto3

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TICKETS_TABLE_NAME"])


def lambda_handler(event, context):
    parameters = {p["name"]: p["value"] for p in event.get("parameters", [])}
    description = parameters.get("description", "")

    ticket_id = str(uuid.uuid4())
    table.put_item(
        Item={
            "ticket_id": ticket_id,
            "description": description,
            "status": "open",
            "created_at": int(time.time()),
        }
    )

    return _agent_response(event, {"ticket_id": ticket_id, "status": "open"})


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
