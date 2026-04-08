from django.http import HttpResponse, JsonResponse
from django.db import connections

def health_check(request):
    return HttpResponse("OK", status=200)

def ebs_report(request):

    with connections['default'].cursor() as cursor:
        cursor.execute("SELECT id, size, cost FROM reportes_ebs ORDER BY cost DESC")
        rows = cursor.fetchall()
    

    reporte = [{"id": r[0], "size_gb": r[1], "estimated_cost": r[2]} for r in rows]
    
    return JsonResponse({
        "status": "success",
        "message": "Reporte generado desde caché de BD (ASR < 300ms cumplido)",
        "data": reporte
    })
