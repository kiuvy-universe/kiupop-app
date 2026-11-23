package agent

import (
	"slices"
	"strings"
	"testing"
	"time"
)

func discoveryBlueprint() Blueprint {
	bp := NewBlueprint()
	bp.Discovery = newDiscovery()
	return bp
}

func TestParseChannels(t *testing.T) {
	cases := map[string][]string{
		"Me compran por WhatsApp":                    {ChannelWhatsApp},
		"Por Instagram y a veces por el whats":       {ChannelWhatsApp, ChannelInstagram},
		"En la feria del agricultor y por Facebook":  {ChannelFacebook, ChannelInPerson},
		"Todavía no vendo":                           {ChannelNone},
		"todavía no vendo mucho, solo por instagram": {ChannelInstagram},
		"no sé": nil,
	}
	for text, want := range cases {
		if got := ParseChannels(text); !slices.Equal(got, want) {
			t.Errorf("ParseChannels(%q) = %v, want %v", text, got, want)
		}
	}
}

func TestParsePain(t *testing.T) {
	cases := map[string]string{
		"Responder precios uno por uno":     PainPrices,
		"Que me encuentren clientes nuevos": PainReach,
		"Ordenar los pedidos":               PainOrders,
		"Cobrar":                            PainPayments,
		"Estoy empezando":                   PainStarting,
		"nada en especial":                  "",
	}
	for text, want := range cases {
		if got := ParsePain(text); got != want {
			t.Errorf("ParsePain(%q) = %q, want %q", text, got, want)
		}
	}
}

func TestDiscoveryAsksEachFilterOnceThenProposes(t *testing.T) {
	bp := discoveryBlueprint()
	bp.Products = []DraftProduct{{ID: "p1", Name: "Ramos", CopyStatus: "pending"}}
	if f := nextDiscoveryField(bp); f != FieldChannels {
		t.Fatalf("offer is known from the products; first filter should be channels, got %q", f)
	}
	bp.Discovery.Asked = append(bp.Discovery.Asked, FieldChannels)
	// An unclear answer is not asked again (no loops): Kiu moves on.
	stepDiscovery(&bp, "mmm no sé", FieldChannels)
	if f := nextDiscoveryField(bp); f != FieldPain {
		t.Fatalf("got %q, want pain", f)
	}
	bp.Discovery.Asked = append(bp.Discovery.Asked, FieldPain)
	stepDiscovery(&bp, "Responder precios uno por uno", FieldPain)
	if bp.Discovery.Pain != PainPrices {
		t.Fatalf("pain = %q", bp.Discovery.Pain)
	}
	if f := nextDiscoveryField(bp); f != "" {
		t.Fatalf("everything asked, got %q", f)
	}
}

func TestDiscoveryOnlyReadsChannelsWhenAsked(t *testing.T) {
	bp := discoveryBlueprint()
	// First message: a WhatsApp number and the word "precio" are data, not answers.
	stepDiscovery(&bp, "Soy Flores Luna, vendo ramos a buen precio. Mi WhatsApp es 8888-1234", "")
	if len(bp.Discovery.Channels) != 0 || bp.Discovery.Pain != "" {
		t.Fatalf("channels=%v pain=%q read without being asked", bp.Discovery.Channels, bp.Discovery.Pain)
	}
}

func TestDiscoveryAcceptChangeAndSkip(t *testing.T) {
	proposed := func() Blueprint {
		bp := discoveryBlueprint()
		bp.Discovery.Channels = []string{ChannelWhatsApp}
		bp.Discovery.Pain = PainPrices
		bp.Discovery.Asked = []string{FieldProducts, FieldChannels, FieldPain}
		p := RecommendPlan(bp)
		bp.Discovery.Plan, bp.Discovery.Status = &p, DiscoveryProposed
		return bp
	}
	for _, yes := range []string{ReplyAcceptPlan, "sí", "Dale!", "listo", "ok, armemos"} {
		bp := proposed()
		if stepDiscovery(&bp, yes, "") != discoveryBuild || bp.Discovery.Status != DiscoveryAccepted {
			t.Errorf("%q should accept the plan (status %q)", yes, bp.Discovery.Status)
		}
	}
	for _, no := range []string{"ojalá", "sinceramente no sé", "okupado"} {
		bp := proposed()
		if stepDiscovery(&bp, no, "") != discoveryContinue || bp.Discovery.Status != DiscoveryProposed {
			t.Errorf("%q must not accept the plan", no)
		}
	}

	bp := proposed()
	stepDiscovery(&bp, ReplyChangePlan, "")
	if bp.Discovery.Status != DiscoveryAsking || nextDiscoveryField(bp) != FieldChannels || bp.Discovery.Plan != nil {
		t.Fatalf("change should restart the filters: %+v", bp.Discovery)
	}

	bp = proposed()
	stepDiscovery(&bp, "También vendo por Instagram", "")
	if bp.Discovery.Status != DiscoveryAsking || !slices.Contains(bp.Discovery.Channels, ChannelInstagram) {
		t.Fatalf("a new channel while reviewing should re-recommend: %+v", bp.Discovery)
	}

	bp = discoveryBlueprint()
	if stepDiscovery(&bp, ReplyKnowWhat, FieldChannels) != discoveryBuild || bp.Discovery.Status != DiscoverySkipped {
		t.Fatalf("«ya sé lo que quiero» must skip straight to building")
	}
}

func TestRecommendPlanMatrix(t *testing.T) {
	plan := func(channels []string, pain string) Plan {
		bp := discoveryBlueprint()
		bp.Discovery.Channels, bp.Discovery.Pain = channels, pain
		return RecommendPlan(bp)
	}

	ig := plan([]string{ChannelInstagram}, PainReach)
	if !strings.Contains(ig.Recommendation, "Instagram") || ig.Note != "" {
		t.Errorf("instagram: %+v", ig)
	}
	if !slices.Equal(ig.KitChannels, []string{ChannelWhatsApp, ChannelInstagram}) {
		t.Errorf("instagram kit = %v", ig.KitChannels)
	}

	wa := plan([]string{ChannelWhatsApp}, PainPrices)
	if !strings.Contains(wa.Recommendation, "WhatsApp") || wa.Note == "" {
		t.Errorf("whatsapp-only should say a full website is not needed: %+v", wa)
	}
	if !strings.Contains(wa.Actions[0], "precios") {
		t.Errorf("the pain's action goes first: %v", wa.Actions)
	}

	pay := plan([]string{ChannelInPerson}, PainPayments)
	if !strings.Contains(pay.Reason, "todavía no cobra") {
		t.Errorf("payments must be honest about no online charging: %q", pay.Reason)
	}

	none := plan(nil, "")
	if none.Problem == "" || none.Recommendation == "" || none.Goal == "" {
		t.Errorf("unknown answers still give a complete plan: %+v", none)
	}

	for _, p := range []Plan{ig, wa, pay, none} {
		if len(p.Actions) == 0 || len(p.Actions) > 3 {
			t.Errorf("actions must be 1..3: %v", p.Actions)
		}
		// Grounding: the plan never states money. Small counts ("3 estados",
		// "5 pedidos") are goals, not prices; prices start at ₡100 (upsertDraftProducts).
		all := p.Problem + p.Recommendation + p.Reason + p.Note + strings.Join(p.Actions, " ") + p.Goal
		if strings.Contains(all, "₡") || strings.Contains(strings.ToLower(all), "colones") {
			t.Errorf("plan mentions money: %q", all)
		}
		for _, v := range MentionedAmounts(all) {
			if v >= 100 {
				t.Errorf("plan mentions an amount (%d): %q", v, all)
			}
		}
	}
}

func TestKitUsesOnlyNameAndLink(t *testing.T) {
	bp := discoveryBlueprint()
	bp.Business.Name = "Flores Luna"
	bp.Discovery.Channels = []string{ChannelInstagram, ChannelInPerson}
	p := RecommendPlan(bp)
	bp.Discovery.Plan = &p
	kit := KitText(bp, "http://localhost:8080/p/flores-luna")
	for _, want := range []string{"WhatsApp", "Instagram", "mostrador", "Flores Luna", "http://localhost:8080/p/flores-luna"} {
		if !strings.Contains(kit, want) {
			t.Errorf("kit lacks %q:\n%s", want, kit)
		}
	}
	if strings.Contains(kit, "Facebook") {
		t.Errorf("kit offers a channel the merchant does not use:\n%s", kit)
	}
	if KitText(NewBlueprint(), "http://x/p/y") != "" {
		t.Error("no discovery, no kit")
	}
}

func TestProgressStaysAtZeroWhileDiagnosing(t *testing.T) {
	bp := discoveryBlueprint()
	bp.Business.Name = "Flores Luna"
	started := mustTime()
	s := Session{Blueprint: bp, FirstMessageAt: &started}
	if p := ComputeProgress(s, nil, false); p.Percent != 0 {
		t.Fatalf("diagnosing must not look like building: %d%%", p.Percent)
	}
	bp.Discovery.Status = DiscoveryAccepted
	s.Blueprint = bp
	if p := ComputeProgress(s, nil, false); p.Percent == 0 {
		t.Fatal("after accepting, progress starts")
	}
}

func mustTime() time.Time { return time.Date(2026, 11, 22, 12, 0, 0, 0, time.UTC) }

func TestUploadOfferedOnlyForOnlineStoreFlow(t *testing.T) {
	online := Blueprint{}
	if q := localQuestion(online, FieldProducts, 0); !q.AllowUpload || !strings.Contains(q.Text, "subí tu lista") {
		t.Fatalf("online flow must offer upload: %+v", q)
	}
	for _, ch := range []string{ChannelWhatsApp, ChannelInstagram, ChannelFacebook, ChannelInPerson} {
		bp := Blueprint{Discovery: &Discovery{Status: DiscoveryAccepted, Channels: []string{ch}}}
		for _, f := range []string{FieldProducts, FieldPrices} {
			q := localQuestion(bp, f, 0)
			if q.AllowUpload || strings.Contains(strings.ToLower(q.Text), "subir") {
				t.Fatalf("%s/%s must not offer upload: %+v", ch, f, q)
			}
		}
	}
	skipped := Blueprint{Discovery: &Discovery{Status: DiscoverySkipped, Channels: []string{ChannelWhatsApp}}}
	if !skipped.OnlineStoreFlow() {
		t.Fatal("'Ya sé lo que quiero' goes straight to the online store flow")
	}
}

func TestGuideAndPriceListForSocialChannels(t *testing.T) {
	bp := Blueprint{
		Business:  BusinessProfile{Name: "Flores Ana"},
		Products:  []DraftProduct{{Name: "Ramo de rosas", PriceMinor: 1500000}, {Name: "Girasoles"}},
		Discovery: &Discovery{Status: DiscoveryAsking, Channels: []string{ChannelInstagram, ChannelWhatsApp}, Pain: PainPrices},
	}
	p := RecommendPlan(bp)
	if len(p.Guide) != 2 || !strings.Contains(PlanText(bp, p), "Cómo armar tu catálogo") {
		t.Fatalf("guide missing: %+v", p.Guide)
	}
	bp.Discovery.Plan = &p
	kit := KitText(bp, "https://x.test/p/flores")
	if !strings.Contains(kit, "Ramo de rosas — ₡15.000") || strings.Contains(kit, "Girasoles") {
		t.Fatalf("price list must list only priced products:\n%s", kit)
	}
}

func TestDiscoveryReviewFixes(t *testing.T) {
	if got := ParseChannels("Hago instalación de repuestos en mi localidad"); len(got) != 0 {
		t.Fatalf("substring channel match: %v", got)
	}
	if got := ParseChannels("Vendo por insta y en ferias"); len(got) != 2 {
		t.Fatalf("channels = %v, want instagram + in person", got)
	}
	if !changeRe.MatchString("Sí, pero cambiá el canal") || !changeRe.MatchString("mejor por Instagram") {
		t.Fatal("voseo change not detected")
	}
	if changeRe.MatchString("Sí, armemos esto") {
		t.Fatal("plain accept read as change")
	}
	if isCommandReply("Vendo velas, ya sé lo que quiero") || !isCommandReply("Ya sé lo que quiero") {
		t.Fatal("command detection must match the whole message only")
	}
}
