"""Standard domain and HTTP exceptions."""
from fastapi import HTTPException, status


class DomainException(Exception):
    """Base domain business rule violation."""
    def __init__(self, message: str, code: str = "DOMAIN_ERROR"):
        super().__init__(message)
        self.message = message
        self.code = code


class EntityNotFoundException(HTTPException):
    def __init__(self, entity_name: str, entity_id: any):
        super().__init__(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"{entity_name} with id {entity_id} was not found.",
        )


class PermissionDeniedException(HTTPException):
    def __init__(self, detail: str = "You do not have permission to perform this action."):
        super().__init__(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=detail,
        )


class TenantMismatchException(HTTPException):
    def __init__(self, detail: str = "Resource belongs to another organization."):
        super().__init__(
            status_code=status.HTTP_404_NOT_FOUND,  # Conceal tenant existence
            detail=detail,
        )
