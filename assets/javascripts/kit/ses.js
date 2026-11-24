// Redmine Kit AWS SES: the plugin's module for the new UI, built from frontend/src by `npm run build` (frontend/vite.config.js).
// Edit the source, not this file. React, @redmine-kit/ui and @redmine-kit/plugin come from the app (the shell's import map).
import { useState } from "react";
import { AttrGrid, AttrGridSkeleton, Button, CardBody, CardSection, Checkbox, DataTable, DataTableSkeleton, EmptyState, FormActions, FormActionsSkeleton, FormRow, Icon, Input, Notice, RequestErrorState, SegmentedControl, Select, Skeleton, SkeletonRegion, Textarea, confirmAction, useFormDirty } from "@redmine-kit/ui";
import { AppLink, CardHeaderActions, useApiErrorTexts, useExtensionContext, useKitMutation, useKitQuery, useT } from "@redmine-kit/plugin";
import { Fragment, jsx, jsxs } from "react/jsx-runtime";
// src/api.ts
var sesPaths = {
	/** GET: the Email sending tab */
	sending: "/admin/aws/mail_sending.json",
	/** POST { tab }: reads the state of SES and DNS again */
	refresh: "/admin/aws/mail_sending/refresh.json",
	/** POST { address }: removes an address from the suppression list */
	unsuppress: "/admin/aws/mail_sending/unsuppress.json",
	/** GET (?dropped=1: dropped email only): the Email receiving tab; POST { settings }: saves its settings */
	receiving: "/admin/aws/mail_receiving.json",
	/** POST { ids }: imports the email again */
	reimport: "/admin/aws/mail_receiving/reimport.json",
	/** POST: Redmine's test email to the administrator (Administration › Settings › Email notifications) */
	testEmail: "/admin/test_email.json",
	/** the failed mail jobs of Redmine Kit AWS SQS */
	failedJobs: "/admin/aws/jobs?mail=1",
	/** GET / PATCH: the Email tab of a project's settings */
	project: (identifier) => `/projects/${encodeURIComponent(identifier)}/aws_ses_mail_setting.json`
};
/**
* When the state of SES and DNS was read and 最新の情報に更新 (reads it again, for both tabs), in the card's header as the
* tab's action (the classic pages' contextual links at the top right).
*/
function RefreshAction({ updated, busy, onRefresh }) {
	const t = useT();
	return /* @__PURE__ */ jsxs(CardHeaderActions, { children: [updated && /* @__PURE__ */ jsx("span", {
		className: "text-meta text-text-muted",
		children: t("label_aws_ses_mail_updated", { time: updated })
	}), /* @__PURE__ */ jsx(Button, {
		icon: "refresh",
		disabled: busy,
		onClick: onRefresh,
		children: t("button_aws_ses_mail_refresh")
	})] });
}
/** Values as label and value pairs (the classic pages' aws_admin/values). */
function ValueRows({ rows }) {
	return /* @__PURE__ */ jsx("div", {
		className: "px-gutter",
		children: /* @__PURE__ */ jsx(AttrGrid, {
			columns: 1,
			labelWidth: 175,
			items: rows.map((row) => ({
				label: row.name,
				value: row.value
			}))
		})
	});
}
/** A section of the stored state: the error of reading it, its values, or 表示するデータがありません. */
function StateValues({ section }) {
	if (section.error) return /* @__PURE__ */ jsx(Notice, {
		tone: "danger",
		text: section.error,
		wrap: true
	});
	return section.rows ? /* @__PURE__ */ jsx(ValueRows, { rows: section.rows }) : /* @__PURE__ */ jsx(EmptyState, {});
}
/** An action's notice and errors, above the sections. */
function ActionResult({ result, errors }) {
	return /* @__PURE__ */ jsxs(Fragment, { children: [result?.notice && /* @__PURE__ */ jsx(Notice, {
		tone: "neutral",
		text: result.notice
	}), errors.length > 0 && /* @__PURE__ */ jsx(Notice, {
		tone: "danger",
		role: "alert",
		text: errors.join("\n"),
		wrap: true
	})] });
}
// src/AwsSesMailSending.tsx
function AwsSesMailSending() {
	const t = useT();
	const query = useKitQuery(sesPaths.sending);
	const action = useKitMutation();
	const errorTexts = useApiErrorTexts();
	const [result, setResult] = useState(null);
	const run = (path, body = {}) => {
		setResult(null);
		action.mutate({
			method: "post",
			path,
			body
		}, { onSuccess: (data) => setResult(data ?? null) });
	};
	const columns = [
		{
			key: "mail",
			label: t("field_mail"),
			type: "text",
			value: (r) => r.destination.address
		},
		{
			key: "user",
			label: t("label_user"),
			type: "text",
			value: (r) => r.destination.user ?? ""
		},
		{
			key: "reason",
			label: t("label_aws_ses_mail_reason"),
			type: "text",
			value: (r) => r.destination.reason
		},
		{
			key: "updated",
			label: t("field_updated_on"),
			type: "text",
			align: "right",
			value: (r) => r.destination.last_update
		},
		{
			key: "actions",
			label: t("button_aws_ses_mail_unsuppress"),
			hasLabel: false,
			type: "actions",
			value: () => [{
				icon: "delete",
				label: t("button_aws_ses_mail_unsuppress"),
				action: "unsuppress",
				danger: true
			}]
		}
	];
	if (query.isError) return /* @__PURE__ */ jsx(CardBody, { children: /* @__PURE__ */ jsx(RequestErrorState, {
		error: query.error,
		onRetry: () => void query.refetch(),
		retrying: query.isFetching
	}) });
	const data = query.data;
	return /* @__PURE__ */ jsxs(Fragment, { children: [/* @__PURE__ */ jsx(RefreshAction, {
		updated: data?.updated ?? null,
		busy: !data || action.isPending,
		onRefresh: () => run(sesPaths.refresh, { tab: "mail_sending" })
	}), /* @__PURE__ */ jsxs(CardBody, { children: [
		/* @__PURE__ */ jsx(ActionResult, {
			result,
			errors: errorTexts(action.error)
		}),
		/* @__PURE__ */ jsxs(CardSection, {
			line: false,
			heading: t("label_aws_ses_mail_account"),
			children: [/* @__PURE__ */ jsxs("div", {
				className: "mb-3 flex flex-wrap items-center gap-2 px-gutter",
				children: [/* @__PURE__ */ jsx(Button, {
					size: 28,
					disabled: !data || action.isPending,
					onClick: () => run(sesPaths.testEmail),
					children: t("label_send_test_email")
				}), data?.failed_jobs && /* @__PURE__ */ jsx(Button, {
					size: 28,
					variant: "plain",
					asChild: true,
					children: /* @__PURE__ */ jsx(AppLink, {
						href: sesPaths.failedJobs,
						children: t("label_aws_ses_mail_failed")
					})
				})]
			}), data ? /* @__PURE__ */ jsx(StateValues, { section: data.account }) : /* @__PURE__ */ jsx(RowsSkeleton, { labels: [
				"enforcement_status",
				"sending_enabled",
				"production_access",
				"quota",
				"sent_last_24_hours",
				"rate"
			].map((k) => t(`label_aws_ses_mail_${k}`)) })]
		}),
		/* @__PURE__ */ jsx(CardSection, {
			heading: t("label_aws_ses_mail_domain"),
			children: !data ? /* @__PURE__ */ jsx(RowsSkeleton, { labels: [
				t("label_aws_ses_mail_domain"),
				t("label_aws_ses_mail_verified"),
				"DKIM"
			] }) : data.domain === null ? /* @__PURE__ */ jsx(Notice, {
				tone: "warning",
				text: t("text_aws_ses_mail_no_domain"),
				wrap: true
			}) : /* @__PURE__ */ jsx(StateValues, { section: data.identity })
		}),
		/* @__PURE__ */ jsx(CardSection, {
			heading: t("label_aws_ses_mail_suppressed"),
			children: !data ? /* @__PURE__ */ jsx(SkeletonRegion, {
				label: t("label_loading"),
				className: "px-gutter",
				children: /* @__PURE__ */ jsx(Skeleton, { width: "60%" })
			}) : data.suppressed.error ? /* @__PURE__ */ jsx(Notice, {
				tone: "danger",
				text: data.suppressed.error,
				wrap: true
			}) : !data.suppressed.rows?.length ? /* @__PURE__ */ jsx(EmptyState, {}) : /* @__PURE__ */ jsx(DataTable, {
				label: t("label_aws_ses_mail_suppressed"),
				columns,
				rows: data.suppressed.rows.map((destination) => ({
					id: destination.address,
					destination
				})),
				onAction: (id) => confirmAction({
					title: t("label_aws_ses_mail_unsuppress_title", { address: id }),
					message: t("text_aws_ses_mail_unsuppress_confirm", { address: id }),
					action: t("button_aws_ses_mail_unsuppress"),
					onConfirm: () => run(sesPaths.unsuppress, { address: id })
				})
			})
		})
	] })] });
}
/** A section's values while the tab loads: its labels (the page's), each value a bar. */
function RowsSkeleton({ labels }) {
	const t = useT();
	return /* @__PURE__ */ jsx(SkeletonRegion, {
		label: t("label_loading"),
		className: "px-gutter",
		children: /* @__PURE__ */ jsx(AttrGridSkeleton, {
			columns: 1,
			labelWidth: 175,
			items: labels.map((label) => ({
				label,
				width: 80
			}))
		})
	});
}
// src/AwsSesMailReceiving.tsx
function useMailColumns() {
	const t = useT();
	return [
		{
			key: "check",
			type: "check"
		},
		{
			key: "received",
			label: t("label_aws_ses_mail_received_at"),
			type: "text",
			value: (r) => r.mail.received_at
		},
		{
			key: "from",
			label: t("label_aws_ses_mail_from"),
			type: "text",
			value: (r) => r.mail.from
		},
		{
			key: "subject",
			label: t("field_subject"),
			type: "text",
			value: (r) => r.mail.subject
		},
		{
			key: "project",
			label: t("label_project"),
			type: "text",
			value: (r) => r.mail.project?.name ?? "",
			cell: (r) => r.mail.project ? /* @__PURE__ */ jsx(AppLink, {
				href: `/projects/${encodeURIComponent(r.mail.project.identifier)}`,
				children: r.mail.project.name
			}) : null
		},
		{
			key: "verdicts",
			label: t("label_aws_ses_mail_verdicts"),
			type: "text",
			value: (r) => r.mail.verdicts
		},
		{
			key: "result",
			label: t("label_aws_ses_mail_result"),
			type: "text",
			value: (r) => r.mail.result,
			cell: (r) => r.mail.issue_id ? /* @__PURE__ */ jsx(AppLink, {
				href: `/issues/${r.mail.issue_id}`,
				children: r.mail.result
			}) : r.mail.result
		}
	];
}
function AwsSesMailReceiving() {
	const t = useT();
	const [dropped, setDropped] = useState(false);
	const query = useKitQuery(sesPaths.receiving, dropped ? { dropped: "1" } : void 0);
	const action = useKitMutation();
	const errorTexts = useApiErrorTexts();
	const [result, setResult] = useState(null);
	const [selected, setSelected] = useState([]);
	const columns = useMailColumns();
	const run = (path, body = {}) => {
		setResult(null);
		action.mutate({
			method: "post",
			path,
			body
		}, { onSuccess: (data) => {
			setResult(data ?? null);
			setSelected([]);
		} });
	};
	if (query.isError) return /* @__PURE__ */ jsx(CardBody, { children: /* @__PURE__ */ jsx(RequestErrorState, {
		error: query.error,
		onRetry: () => void query.refetch(),
		retrying: query.isFetching
	}) });
	const data = query.data;
	const projectColumns = [
		{
			key: "project",
			label: t("label_project"),
			type: "text",
			value: (r) => r.project.name,
			cell: (r) => /* @__PURE__ */ jsx(AppLink, {
				href: `/projects/${encodeURIComponent(r.project.identifier)}`,
				children: r.project.name
			})
		},
		{
			key: "mail",
			label: t("field_mail"),
			type: "text",
			value: (r) => r.address
		},
		{
			key: "receive",
			label: t("label_aws_ses_mail_receive"),
			type: "text",
			align: "center",
			value: (r) => r.receive ? t("general_text_Yes") : t("general_text_No"),
			cell: (r) => r.receive ? /* @__PURE__ */ jsx("span", {
				className: "flex justify-center text-accent",
				role: "img",
				"aria-label": t("general_text_Yes"),
				children: /* @__PURE__ */ jsx(Icon, {
					name: "check",
					size: 16
				})
			}) : null
		}
	];
	return /* @__PURE__ */ jsxs(Fragment, { children: [/* @__PURE__ */ jsx(RefreshAction, {
		updated: data?.updated ?? null,
		busy: !data || action.isPending,
		onRefresh: () => run(sesPaths.refresh, { tab: "mail_receiving" })
	}), /* @__PURE__ */ jsxs(CardBody, { children: [
		/* @__PURE__ */ jsx(ActionResult, {
			result,
			errors: errorTexts(action.error)
		}),
		data && !data.bucket && /* @__PURE__ */ jsx(Notice, {
			tone: "warning",
			text: t("text_aws_ses_mail_no_bucket"),
			wrap: true
		}),
		/* @__PURE__ */ jsx(CardSection, {
			line: false,
			heading: t("label_aws_ses_mail_addresses"),
			children: !data ? /* @__PURE__ */ jsx(SkeletonRegion, {
				label: t("label_loading"),
				className: "px-gutter",
				children: /* @__PURE__ */ jsx(AttrGridSkeleton, {
					columns: 1,
					labelWidth: 175,
					items: [
						{ label: t("label_aws_ses_mail_domain") },
						{ label: t("label_aws_ses_mail_global_address") },
						{ label: "MX" }
					]
				})
			}) : data.domain === null ? /* @__PURE__ */ jsx(Notice, {
				tone: "warning",
				text: t("text_aws_ses_mail_no_domain"),
				wrap: true
			}) : /* @__PURE__ */ jsxs("div", {
				className: "flex flex-col gap-3",
				children: [
					data.addresses && /* @__PURE__ */ jsx(ValueRows, { rows: data.addresses }),
					data.warnings.length > 0 && /* @__PURE__ */ jsx("div", { children: data.warnings.map((warning) => /* @__PURE__ */ jsx(Notice, {
						tone: "warning",
						text: warning,
						wrap: true
					}, warning)) }),
					data.projects && /* @__PURE__ */ jsx(DataTable, {
						label: t("label_aws_ses_mail_addresses"),
						columns: projectColumns,
						rows: data.projects.map((row) => ({
							id: row.project.identifier,
							...row
						}))
					})
				]
			})
		}),
		/* @__PURE__ */ jsxs(CardSection, {
			heading: t("label_aws_ses_mail_received"),
			controls: /* @__PURE__ */ jsx(SegmentedControl, {
				size: 28,
				"aria-label": t("label_aws_ses_mail_received"),
				value: dropped ? "dropped" : "all",
				onValueChange: (value) => {
					setDropped(value === "dropped");
					setSelected([]);
				},
				items: [{
					value: "all",
					label: t("label_all")
				}, {
					value: "dropped",
					label: t("label_aws_ses_mail_dropped_only")
				}]
			}),
			children: [selected.length > 0 && /* @__PURE__ */ jsx(Notice, {
				tone: "neutral",
				icon: "none",
				text: /* @__PURE__ */ jsxs("span", {
					className: "flex min-w-0 flex-wrap items-center gap-2",
					children: [/* @__PURE__ */ jsx("span", {
						className: "flex-none",
						children: t("kit.common.selected_items", { count: selected.length })
					}), /* @__PURE__ */ jsx(Button, {
						size: 28,
						disabled: action.isPending,
						onClick: () => confirmAction({
							title: t("button_aws_ses_mail_reimport"),
							message: t("text_aws_ses_mail_reimport_confirm", { count: selected.length }),
							action: t("button_aws_ses_mail_reimport"),
							onConfirm: () => run(sesPaths.reimport, { ids: selected.map(Number) })
						}),
						children: t("button_aws_ses_mail_reimport")
					})]
				})
			}), !data ? /* @__PURE__ */ jsx(DataTableSkeleton, {
				label: t("label_aws_ses_mail_received"),
				loading: t("label_loading"),
				columns,
				rows: 3
			}) : data.received.length === 0 ? /* @__PURE__ */ jsx(EmptyState, {}) : /* @__PURE__ */ jsx(DataTable, {
				label: t("label_aws_ses_mail_received"),
				columns,
				rows: data.received.map((mail) => ({
					id: String(mail.id),
					mail
				})),
				selected,
				onSelectionChange: setSelected
			})]
		}),
		/* @__PURE__ */ jsx(CardSection, {
			heading: t("label_aws_ses_mail_settings"),
			children: data && /* @__PURE__ */ jsx(SettingsForm, { data }, JSON.stringify(data.settings))
		})
	] })] });
}
/** 受信設定: the receiving settings as the page's form has them; 保存 posts them (POST { settings }), Redmine's errors above. */
function SettingsForm({ data }) {
	const t = useT();
	const save = useKitMutation(sesPaths.receiving, "post");
	const errorTexts = useApiErrorTexts();
	const [values, setValues] = useState(data.settings);
	const form = useFormDirty(values);
	const set = (name, value) => setValues({
		...values,
		[name]: value
	});
	const check = (name, label) => /* @__PURE__ */ jsx(Checkbox, {
		checked: values[name] === "1",
		onCheckedChange: (v) => set(name, v === true ? "1" : "0"),
		label
	}, name);
	const errors = errorTexts(save.error);
	return /* @__PURE__ */ jsxs(Fragment, { children: [
		save.isSuccess && !form.dirty && /* @__PURE__ */ jsx(Notice, {
			tone: "neutral",
			role: "status",
			text: t("notice_successful_update")
		}),
		errors.length > 0 && /* @__PURE__ */ jsx(Notice, {
			tone: "danger",
			role: "alert",
			text: errors.join("\n"),
			wrap: true
		}),
		/* @__PURE__ */ jsxs("div", {
			className: "box-content flex max-w-215 flex-col gap-4 px-6",
			children: [
				/* @__PURE__ */ jsx(FormRow, {
					label: t("label_aws_ses_mail_global_address"),
					children: /* @__PURE__ */ jsxs("span", {
						className: "flex items-center gap-1",
						children: [/* @__PURE__ */ jsx(Input, {
							value: values.global_local_part,
							onChange: (e) => set("global_local_part", e.target.value),
							className: "w-40",
							"aria-label": t("label_aws_ses_mail_global_address")
						}), data.domain && /* @__PURE__ */ jsxs("span", { children: ["@", data.domain] })]
					})
				}),
				/* @__PURE__ */ jsx(FormRow, {
					label: t("label_incoming_emails"),
					children: /* @__PURE__ */ jsx(Select, {
						options: data.global_mail,
						value: values.global_mail,
						onChange: (e) => set("global_mail", e.target.value),
						className: "w-60"
					})
				}),
				/* @__PURE__ */ jsx(FormRow, {
					label: t("label_aws_ses_mail_default_project"),
					children: /* @__PURE__ */ jsx(Select, {
						options: [{
							value: "",
							label: ""
						}, ...data.default_projects],
						value: values.default_project,
						onChange: (e) => set("default_project", e.target.value),
						className: "w-60"
					})
				}),
				/* @__PURE__ */ jsx(FormRow, {
					label: t("label_aws_ses_mail_import"),
					group: true,
					children: /* @__PURE__ */ jsxs("div", {
						className: "flex flex-col gap-2",
						children: [check("import_without_dmarc_pass", t("label_aws_ses_mail_import_without_dmarc_pass")), check("import_spam", t("label_aws_ses_mail_import_spam"))]
					})
				}),
				/* @__PURE__ */ jsx(FormRow, {
					label: t("label_project_plural"),
					group: true,
					children: /* @__PURE__ */ jsxs("div", {
						className: "flex flex-col gap-2",
						children: [check("per_project_addresses", t("label_aws_ses_mail_per_project")), check("project_senders", t("label_aws_ses_mail_project_senders"))]
					})
				})
			]
		}),
		/* @__PURE__ */ jsxs(FormActions, {
			edge: true,
			children: [/* @__PURE__ */ jsx(Button, {
				"data-form-cancel": true,
				variant: "ghost",
				disabled: !form.dirty || save.isPending,
				onClick: () => setValues(form.saved),
				children: t("button_cancel")
			}), /* @__PURE__ */ jsx(Button, {
				submit: "primary",
				variant: "primary",
				disabled: !form.dirty || save.isPending,
				onClick: () => save.mutate({ settings: values }, { onSuccess: () => form.markSaved() }),
				children: t("button_save")
			})]
		})
	] });
}
// src/AwsSesProjectMail.tsx
var FIELDS = [
	"receive",
	"tracker_id",
	"category_id",
	"priority_id",
	"assigned_to_id",
	"is_private",
	"unknown_user",
	"forwarders",
	"import_forwarded",
	"forwarded_author"
];
function AwsSesProjectMail() {
	const { project } = useExtensionContext();
	if (!project) return null;
	return /* @__PURE__ */ jsx(ProjectMail, { identifier: project.identifier });
}
function ProjectMail({ identifier }) {
	const query = useKitQuery(sesPaths.project(identifier));
	if (query.isError) return /* @__PURE__ */ jsx(RequestErrorState, {
		error: query.error,
		onRetry: () => void query.refetch(),
		retrying: query.isFetching
	});
	if (!query.data) return /* @__PURE__ */ jsx(FormSkeleton, {});
	return /* @__PURE__ */ jsx(ProjectMailForm, {
		identifier,
		data: query.data
	});
}
function FormSkeleton() {
	const t = useT();
	return /* @__PURE__ */ jsxs(Fragment, { children: [/* @__PURE__ */ jsx(SkeletonRegion, {
		label: t("label_loading"),
		className: "flex flex-col gap-4 px-6 py-section",
		children: Array.from({ length: 6 }, (_, i) => /* @__PURE__ */ jsx(Skeleton, {
			width: "40%",
			height: 32
		}, i))
	}), /* @__PURE__ */ jsx(FormActionsSkeleton, {})] });
}
var truthy = (value) => value === "true" || value === "1";
function ProjectMailForm({ identifier, data }) {
	const t = useT();
	const save = useKitMutation(sesPaths.project(identifier), "patch");
	const errorTexts = useApiErrorTexts();
	const [values, setValues] = useState(data.values);
	const form = useFormDirty(values);
	const editable = (name) => data.editable.includes(name);
	const set = (name, value) => setValues({
		...values,
		[name]: value
	});
	const select = (name, label, options, blank = true) => /* @__PURE__ */ jsx(FormRow, {
		label,
		children: /* @__PURE__ */ jsx(Select, {
			"aria-label": label,
			options: blank ? [{
				value: "",
				label: ""
			}, ...options] : options,
			value: values[name] ?? "",
			disabled: !editable(name),
			onChange: (e) => set(name, e.target.value),
			className: "w-60"
		})
	});
	const check = (name, label, { disabled = false, visible = false } = {}) => /* @__PURE__ */ jsx("span", {
		className: "inline-flex h-8 items-center",
		children: /* @__PURE__ */ jsx(Checkbox, {
			checked: truthy(values[name]),
			disabled: disabled || !editable(name),
			onCheckedChange: (v) => set(name, v === true ? "1" : "0"),
			...visible ? { label } : { "aria-label": label }
		})
	});
	const errors = errorTexts(save.error);
	const changed = Object.fromEntries(FIELDS.filter((name) => editable(name)).map((name) => [name, values[name] ?? ""]));
	return /* @__PURE__ */ jsxs(Fragment, { children: [
		save.isSuccess && !form.dirty && /* @__PURE__ */ jsx(Notice, {
			tone: "neutral",
			role: "status",
			text: t("notice_successful_update")
		}),
		errors.length > 0 && /* @__PURE__ */ jsx(Notice, {
			tone: "danger",
			role: "alert",
			text: errors.join("\n"),
			wrap: true
		}),
		/* @__PURE__ */ jsxs("div", {
			className: "box-content flex max-w-215 flex-col gap-4 px-6 py-section",
			children: [
				/* @__PURE__ */ jsx(FormRow, {
					label: t("field_mail"),
					group: true,
					children: /* @__PURE__ */ jsx("span", {
						className: "inline-flex h-8 items-center",
						children: data.address ?? "-"
					})
				}),
				/* @__PURE__ */ jsx(FormRow, {
					label: t("label_aws_ses_mail_receive"),
					group: true,
					children: check("receive", t("label_aws_ses_mail_receive"), { disabled: data.address === null })
				}),
				select("tracker_id", t("field_tracker"), data.trackers),
				select("category_id", t("field_category"), data.categories),
				select("priority_id", t("field_priority"), data.priorities),
				select("assigned_to_id", t("field_assigned_to"), data.assignees),
				/* @__PURE__ */ jsx(FormRow, {
					label: t("field_is_private"),
					group: true,
					children: check("is_private", t("field_is_private"))
				}),
				select("unknown_user", t("label_aws_ses_mail_unknown_user"), data.unknown_user, false),
				/* @__PURE__ */ jsx(FormRow, {
					label: t("label_aws_ses_mail_forwarders"),
					hint: `${t("text_aws_ses_mail_forwarders_info")} ${t("text_line_separated")}`,
					children: /* @__PURE__ */ jsx(Textarea, {
						"aria-label": t("label_aws_ses_mail_forwarders"),
						rows: 3,
						value: values.forwarders ?? "",
						disabled: !editable("forwarders"),
						onChange: (e) => set("forwarders", e.target.value),
						className: "w-full max-w-120"
					})
				}),
				/* @__PURE__ */ jsx(FormRow, {
					label: t("label_aws_ses_mail_forwarded"),
					group: true,
					children: check("import_forwarded", t("label_aws_ses_mail_import_forwarded"), { visible: true })
				}),
				select("forwarded_author", t("label_aws_ses_mail_forwarded_author"), data.forwarded_author, false)
			]
		}),
		/* @__PURE__ */ jsxs(FormActions, {
			placement: "sticky",
			children: [/* @__PURE__ */ jsx(Button, {
				"data-form-cancel": true,
				variant: "ghost",
				disabled: !form.dirty || save.isPending,
				onClick: () => setValues(form.saved),
				children: t("button_cancel")
			}), /* @__PURE__ */ jsx(Button, {
				submit: "primary",
				variant: "primary",
				keycap: "⌘↵",
				disabled: !form.dirty || save.isPending,
				onClick: () => save.mutate({ aws_ses_project_mail_setting: changed }, { onSuccess: () => form.markSaved() }),
				children: t("button_save")
			})]
		})
	] });
}
export { AwsSesMailReceiving, AwsSesMailSending, AwsSesProjectMail };
