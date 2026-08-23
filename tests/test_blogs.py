"""Blog API tests — public visibility rules, admin-only writes, slug handling, recycle bin."""
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from database import Base, get_db
from dependencies import generate_token
from main import app
from models import BinItem, BlogPost, Organization, OrganizationStatus, OrganizationType, User, UserRole, _utcnow


@pytest.fixture()
def client():
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    Base.metadata.create_all(bind=engine)

    def override_get_db():
        db = TestingSessionLocal()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db

    db = TestingSessionLocal()
    org = Organization(
        id=1,
        slug="techcorp",
        name="TechCorp Global",
        type=OrganizationType.BUSINESS,
        status=OrganizationStatus.ACTIVE,
    )
    db.add(org)

    admin = User(
        name="Org Admin",
        email="admin@test.local",
        role=UserRole.ADMIN,
        is_active=True,
        session_version=1,
    )
    admin.set_password("AdminPass123!")
    mentor = User(
        name="Mentor Jane",
        email="mentor@test.local",
        role=UserRole.MENTOR,
        is_active=True,
        session_version=1,
    )
    mentor.set_password("MentorPass123!")
    intern = User(
        name="Intern Bob",
        email="intern@test.local",
        role=UserRole.INTERN,
        is_active=True,
        session_version=1,
    )
    intern.set_password("InternPass123!")
    db.add_all([admin, mentor, intern])
    db.commit()

    tokens = {
        "admin": generate_token(admin.id, admin.session_version),
        "mentor": generate_token(mentor.id, mentor.session_version),
        "intern": generate_token(intern.id, intern.session_version),
    }
    yield TestClient(app), TestingSessionLocal, tokens
    app.dependency_overrides.pop(get_db, None)
    db.close()
    engine.dispose()


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _create_post(db_session, title: str, status: str = "published", **kwargs) -> dict:
    post = BlogPost(
        title=title,
        slug=kwargs.pop("slug", None) or title.lower().replace(" ", "-"),
        content=kwargs.pop("content", f"<p>{title} body</p>"),
        status=status,
        published_at=_utcnow() if status == "published" else None,
        **kwargs,
    )
    db_session.add(post)
    db_session.flush()
    ref = {"id": post.id, "slug": post.slug}
    db_session.commit()
    return ref


def test_public_list_returns_only_published_with_pagination(client):
    tc, SessionLocal, _ = client
    db = SessionLocal()
    for i in range(3):
        _create_post(db, f"Published Post {i}")
    _create_post(db, "Hidden Draft", status="draft")
    db.close()

    res = tc.get("/api/blogs")
    assert res.status_code == 200
    data = res.json()
    assert data["total"] == 3
    assert len(data["items"]) == 3
    # List responses must not include full bodies.
    assert all("content" not in item for item in data["items"])

    paged = tc.get("/api/blogs", params={"page": 2, "per_page": 2}).json()
    assert paged["total"] == 3
    assert len(paged["items"]) == 1


def test_public_detail_by_slug_and_404s(client):
    tc, SessionLocal, _ = client
    db = SessionLocal()
    post = _create_post(db, "Visible Story")
    _create_post(db, "Secret Draft", status="draft")
    db.close()

    res = tc.get(f"/api/blogs/{post['slug']}")
    assert res.status_code == 200
    assert res.json()["title"] == "Visible Story"
    assert "body" in res.json()["content"]

    assert tc.get("/api/blogs/no-such-post").status_code == 404
    assert tc.get("/api/blogs/secret-draft").status_code == 404


def test_search_and_tag_filters(client):
    tc, SessionLocal, _ = client
    db = SessionLocal()
    _create_post(db, "FastAPI Guide", tags="python,backend")
    _create_post(db, "React Tips", tags="frontend")
    db.close()

    assert tc.get("/api/blogs", params={"search": "fastapi"}).json()["total"] == 1
    assert tc.get("/api/blogs", params={"tag": "frontend"}).json()["total"] == 1
    assert tc.get("/api/blogs", params={"tag": "python"}).json()["items"][0]["tags"] == ["python", "backend"]


def test_create_requires_admin(client):
    tc, _, tokens = client
    payload = {"title": "New Post", "content": "<p>Hello</p>"}

    assert tc.post("/api/blogs", json=payload).status_code == 403
    assert tc.post("/api/blogs", json=payload, headers=_auth(tokens["intern"])).status_code == 403
    assert tc.post("/api/blogs", json=payload, headers=_auth(tokens["mentor"])).status_code == 403

    res = tc.post("/api/blogs", json=payload, headers=_auth(tokens["admin"]))
    assert res.status_code == 200
    body = res.json()
    assert body["slug"] == "new-post"
    assert body["status"] == "draft"
    assert body["published_at"] is None


def test_slug_auto_suffix_on_conflict(client):
    tc, _, tokens = client
    headers = _auth(tokens["admin"])
    first = tc.post("/api/blogs", json={"title": "Launch Day", "content": "one"}, headers=headers).json()
    second = tc.post("/api/blogs", json={"title": "Launch Day", "content": "two"}, headers=headers).json()
    assert first["slug"] == "launch-day"
    assert second["slug"] == "launch-day-2"


def test_publish_transition_sets_published_at(client):
    tc, SessionLocal, tokens = client
    db = SessionLocal()
    post = _create_post(db, "Transition Me", status="draft")
    db.close()
    headers = _auth(tokens["admin"])

    res = tc.put(f"/api/blogs/{post['id']}", json={"status": "published"}, headers=headers).json()
    assert res["status"] == "published"
    assert res["published_at"] is not None

    res = tc.put(f"/api/blogs/{post['id']}", json={"status": "draft"}, headers=headers).json()
    assert res["status"] == "draft"
    assert res["published_at"] is None

    bad = tc.put(f"/api/blogs/{post['id']}", json={"status": "bogus"}, headers=headers)
    assert bad.status_code == 422


def test_update_regenerates_slug_from_title(client):
    tc, SessionLocal, tokens = client
    db = SessionLocal()
    post = _create_post(db, "Old Title Here")
    db.close()

    res = tc.put(f"/api/blogs/{post['id']}", json={"title": "Brand New Title"}, headers=_auth(tokens["admin"])).json()
    assert res["slug"] == "brand-new-title"


def test_admin_list_includes_drafts_requires_auth(client):
    tc, SessionLocal, tokens = client
    db = SessionLocal()
    _create_post(db, "Live One")
    _create_post(db, "Draft One", status="draft")
    db.close()

    assert tc.get("/api/blogs/admin/all").status_code == 403
    assert tc.get("/api/blogs/admin/all", headers=_auth(tokens["intern"])).status_code == 403

    data = tc.get("/api/blogs/admin/all", headers=_auth(tokens["admin"])).json()
    assert data["total"] == 2
    drafts_only = tc.get("/api/blogs/admin/all", params={"status": "draft"}, headers=_auth(tokens["admin"])).json()
    assert drafts_only["total"] == 1
    assert drafts_only["items"][0]["title"] == "Draft One"


def test_delete_moves_to_bin_and_hides_post(client):
    tc, SessionLocal, tokens = client
    db = SessionLocal()
    admin = db.query(User).filter_by(email="admin@test.local").first()
    post = _create_post(db, "Doomed Post", author_id=admin.id)
    post_id = post["id"]
    db.close()

    assert tc.delete("/api/blogs/999999", headers=_auth(tokens["admin"])).status_code == 404
    assert tc.delete(f"/api/blogs/{post_id}", headers=_auth(tokens["mentor"])).status_code == 403

    res = tc.delete(f"/api/blogs/{post_id}", headers=_auth(tokens["admin"]))
    assert res.status_code == 200
    assert res.json() == {"ok": True}

    assert tc.get("/api/blogs/doomed-post").status_code == 404
    db = SessionLocal()
    try:
        bin_item = db.query(BinItem).filter_by(entity_type="blog_post", entity_id=post_id).first()
        assert bin_item is not None
        assert bin_item.title == "Doomed Post"
    finally:
        db.close()


def test_draft_detail_visible_to_admin_preview(client):
    tc, SessionLocal, tokens = client
    db = SessionLocal()
    _create_post(db, "Preview Only", status="draft")
    db.close()

    assert tc.get("/api/blogs/preview-only").status_code == 404
    res = tc.get("/api/blogs/preview-only", headers=_auth(tokens["admin"]))
    assert res.status_code == 200
    assert res.json()["status"] == "draft"


def test_sitemap_includes_published_posts_only(client):
    from config import Config

    tc, SessionLocal, tokens = client
    db = SessionLocal()
    _create_post(db, "Sitemap Live Post", slug="sitemap-live-post")
    _create_post(db, "Hidden From Sitemap", status="draft")
    db.close()

    base = (Config.PUBLIC_SITE_URL or "https://internhub-sas-production.up.railway.app").rstrip("/")

    res = tc.get("/sitemap.xml")
    assert res.status_code == 200
    assert "xml" in res.headers["content-type"]

    body = res.text
    assert f"<loc>{base}/</loc>" in body
    assert f"<loc>{base}/blogs</loc>" in body
    assert f"<loc>{base}/blogs/sitemap-live-post</loc>" in body
    assert "<lastmod>" in body

    # Drafts and deleted posts must never appear.
    assert "hidden-from-sitemap" not in body
    db = SessionLocal()
    draft = (
        db.query(BlogPost)
        .filter(BlogPost.slug == "hidden-from-sitemap")
        .first()
    )
    draft_id = draft.id if draft else None
    live = db.query(BlogPost).filter(BlogPost.slug == "sitemap-live-post").first()
    if live and draft_id:
        from models import BinEntityType
        from recycle_bin import move_to_bin
        admin = db.query(User).filter_by(email="admin@test.local").first()
        move_to_bin(db, admin, BinEntityType.BLOG_POST, live)
        db.commit()
    db.close()

    body_after = tc.get("/sitemap.xml").text
    assert "sitemap-live-post" not in body_after

    # The {slug} route must still resolve — sitemap path must not shadow it.
    assert tc.get("/api/blogs/sitemap-live-post").status_code == 404  # soft-deleted above
