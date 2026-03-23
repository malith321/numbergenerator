# ── Developer Group ───────────────────────────────────────────────────────────
resource "aws_iam_group" "developers" {
  name = "${var.project}-developers"
}

resource "aws_iam_policy" "developer" {
  name        = "${var.project}-developer-policy"
  description = "Developer access to prime service resources"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ecr:*",
        "ecs:*",
        "rds:Describe*",
        "rds:ListTagsForResource",
        "ec2:Describe*",
        "logs:*",
        "cloudwatch:*",
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "iam:GetRole",
        "iam:PassRole"
      ]
      Resource = "*"
      Condition = {
        StringEquals = {
          "aws:RequestedRegion" = var.aws_region
        }
      }
    }]
  })
}

resource "aws_iam_group_policy_attachment" "developer" {
  group      = aws_iam_group.developers.name
  policy_arn = aws_iam_policy.developer.arn
}

# ── Readonly Group ────────────────────────────────────────────────────────────
resource "aws_iam_group" "readonly" {
  name = "${var.project}-readonly"
}

resource "aws_iam_policy" "readonly" {
  name        = "${var.project}-readonly-policy"
  description = "Read-only access to prime service metrics and logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ecs:Describe*",
        "ecs:List*",
        "logs:GetLogEvents",
        "logs:DescribeLogStreams",
        "logs:DescribeLogGroups",
        "logs:FilterLogEvents",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:ListMetrics",
        "cloudwatch:DescribeAlarms",
        "rds:Describe*",
        "ec2:Describe*"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_group_policy_attachment" "readonly" {
  group      = aws_iam_group.readonly.name
  policy_arn = aws_iam_policy.readonly.arn
}

# ── Developer Users ───────────────────────────────────────────────────────────
resource "aws_iam_user" "developers" {
  for_each = toset(var.developer_users)
  name     = each.value
  tags     = { Environment = var.environment, Role = "developer" }
}

resource "aws_iam_user_group_membership" "developers" {
  for_each = toset(var.developer_users)
  user     = aws_iam_user.developers[each.value].name
  groups   = [aws_iam_group.developers.name]
}

# ── Readonly Users ────────────────────────────────────────────────────────────
resource "aws_iam_user" "readonly" {
  for_each = toset(var.readonly_users)
  name     = each.value
  tags     = { Environment = var.environment, Role = "readonly" }
}

resource "aws_iam_user_group_membership" "readonly" {
  for_each = toset(var.readonly_users)
  user     = aws_iam_user.readonly[each.value].name
  groups   = [aws_iam_group.readonly.name]
}
