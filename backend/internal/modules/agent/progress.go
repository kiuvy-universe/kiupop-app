package agent

import "github.com/kiuvy-universe/kiupop/backend/internal/platform/storefront"

// Task is one visible build step.
type Task struct {
	Key    string `json:"key"`
	Label  string `json:"label"`
	Status string `json:"status"` // pending | running | done | needs_input | skipped | failed
}

// Progress is what drives Kiu's bubble. Percent only reaches 100 when the
// backend has validated readiness for the current revision.
type Progress struct {
	Percent int    `json:"percent"`
	Tasks   []Task `json:"tasks"`
	Ready   bool   `json:"ready"`
}

var taskWeights = map[string]int{"profile": 15, "draft": 10, "catalog": 20, "copy": 10, "theme": 15, "contact": 10, "delivery": 5, "preview": 15}

// ComputeProgress derives build progress from durable state (no in-memory counters).
func ComputeProgress(s Session, jobs []JobState, aiCopy bool) Progress {
	bp := s.Blueprint
	active := func(kind string) bool {
		for _, j := range jobs {
			if j.Kind == kind && (j.Status == "queued" || j.Status == "running") {
				return true
			}
		}
		return false
	}
	failed := func(kind string) bool {
		for _, j := range jobs {
			if j.Kind == kind && j.Status == "failed" {
				return true
			}
		}
		return false
	}
	started := s.FirstMessageAt != nil && !bp.Discovery.Active() // the diagnosis builds nothing
	st := func(done bool, running bool, needsInput bool) string {
		switch {
		case done:
			return "done"
		case running:
			return "running"
		case needsInput && started:
			return "needs_input"
		}
		return "pending"
	}
	ready := s.ReadyRevision > 0 && len(bp.Readiness()) == 0
	tasks := []Task{
		{"profile", "Entender tu negocio", st(bp.Business.Name != "", false, true)},
		{"draft", "Crear el borrador", st(s.StoreID != "", false, false)},
		{"catalog", "Armar el catálogo", st(len(bp.PricedProducts()) > 0, false, true)},
		{"copy", "Escribir descripciones", ""},
		{"theme", "Diseñar el estilo", st(storefront.ValidTemplate(bp.Theme.Template), active("theme"), false)},
		{"contact", "Conectar WhatsApp", st(bp.Contact.WhatsApp != "", false, true)},
		{"delivery", "Opciones de entrega", ""},
		{"preview", "Vista previa lista", st(ready && s.PreviewRevision >= s.ReadyRevision, active("preview"), false)},
	}
	for i := range tasks {
		switch tasks[i].Key {
		case "copy":
			switch {
			case !aiCopy:
				tasks[i].Status, tasks[i].Label = "skipped", "Descripciones (requiere IA)"
			case active("copy"):
				tasks[i].Status = "running"
			case len(bp.Products) > 0:
				tasks[i].Status = "done"
				if failed("copy") {
					tasks[i].Status = "failed"
				}
			default:
				tasks[i].Status = "pending"
			}
		case "delivery":
			switch {
			case len(bp.Delivery.Modes) > 0:
				tasks[i].Status = "done"
			case bp.skipped(FieldDelivery):
				tasks[i].Status = "skipped"
			default:
				tasks[i].Status = st(false, false, true)
			}
		}
	}
	pct := 0
	for _, t := range tasks {
		if t.Status == "done" || t.Status == "skipped" || t.Status == "failed" {
			pct += taskWeights[t.Key]
		} else if t.Status == "running" {
			pct += taskWeights[t.Key] / 2
		}
	}
	if !ready && pct > 95 {
		pct = 95 // 100% (and POP) only after the backend confirms readiness
	}
	if ready {
		pct = 100
	}
	if !started {
		pct = 0
	}
	return Progress{Percent: pct, Tasks: tasks, Ready: ready}
}
